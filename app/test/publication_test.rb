require_relative 'test_helper'

class PublicationTest < KelmscottTest
  # Remplace le sandbox, qui ne tourne que sur le serveur : il simule le build et la synchronisation
  class FakeSandbox
    attr_accessor :fetch_result, :compile_result, :sync_result, :public_files, :public_links, :public_fifos, :site_files, :error_to_raise
    attr_reader :synced

    def initialize(site)
      @site = site
      @fetch_result = true
      @compile_result = true
      @sync_result = true
      @public_files = ['index.html']
      @public_links = []
      @public_fifos = []
      # Chemin dans le dossier du site => taille en Mo
      @site_files = {}
    end

    def fetch(_git_url)
      raise error_to_raise if error_to_raise
      fetch_result
    end

    def compile
      FileUtils.mkdir_p(@site.public_path)
      public_files.each { |file| File.write(File.join(@site.public_path, file), 'ok') }
      public_links.each { |link| File.symlink('/etc/hosts', File.join(@site.public_path, link)) }
      public_fifos.each { |fifo| File.mkfifo(File.join(@site.public_path, fifo)) }
      site_files.each do |file, megabytes|
        path = File.join(@site.path, file)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, 'x' * megabytes * 1024**2)
      end
      @site.append_log("Compilation simulée\n")
      compile_result
    end

    def sync(sync_method, environment, secrets)
      @synced = [sync_method, environment, secrets]
      @site.append_log("Synchronisation simulée\n")
      sync_result
    end
  end

  class FakePublication < Publication
    public def sandbox
      @fake_sandbox ||= FakeSandbox.new(site)
    end

    private

    # Les erreurs attendues sont vérifiées dans le log, inutile de les afficher
    def warn(*); end
  end

  def publication
    @publication ||= FakePublication.new('universite', 'site', 'https://example.org/site.git', 'dxfl', {})
  end

  def status
    read_state('universite', 'site', 'status')
  end

  def log
    read_state('universite', 'site', 'log')
  end

  def test_success
    publication.run
    assert_equal 'success', status
    assert_match(/\ADébut : /, log)
    assert_includes log, 'Compilation simulée'
    assert_includes log, 'Synchronisation simulée'
    %w[Récupération Compilation Synchronisation].each do |step|
      assert_match(/^  #{step} : \d+ s$/, log)
    end
    assert_match(/^Fin : /, log)
    assert_match(/^Durée : \d+ s$/, log)
    assert_match(/^Poids : \d+ Mo$/, log)
  end

  def test_size_details
    publication.sandbox.site_files = {
      'repository/.git/pack' => 2,
      'repository/content/page.md' => 1,
      '.npm/paquet.tgz' => 4,
      '.cache/hugo/ressource' => 5
    }
    publication.run
    assert_includes log, "Poids : 12 Mo\n"
    {
      'Site compilé (public)' => 0,
      'Historique git (.git)' => 2,
      'Sources' => 1,
      'Caches' => 9
    }.each do |name, megabytes|
      assert_includes log, "  #{name} : #{megabytes} Mo\n"
    end
  end

  def test_records_disk_usage
    publication.run
    assert_operator read_state('universite', 'site', 'size').to_i, :>, 0
  end

  def test_fetch_failure
    publication.sandbox.fetch_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Récupération du dépôt impossible'
    refute_match(/^  Compilation : /, log)
    assert_match(/^Fin : /, log)
  end

  def test_compile_failure
    publication.sandbox.compile_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Échec de la compilation'
    refute_includes log, 'Synchronisation simulée'
    refute_match(/^  Synchronisation : /, log)
  end

  def test_sync_failure
    publication.sandbox.sync_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Échec de la synchronisation'
    assert_match(/^  Synchronisation : /, log)
  end

  # Les secrets arrivent chiffrés, et ne sont déchiffrés que pour la synchronisation
  def test_sync_decrypts_secrets
    public_key, = configure_keys
    variables = { 'S3_BUCKET' => 'bucket', 'AWS_SECRET_ACCESS_KEY' => encrypt(public_key, 'secret') }
    publication = FakePublication.new('universite', 'site', 'https://example.org/site.git', 's3', variables)
    publication.run
    assert_equal ['s3', { 'S3_BUCKET' => 'bucket', 'AWS_SECRET_ACCESS_KEY' => 'secret' }, ['secret']], publication.sandbox.synced
  end

  def test_refuses_symbolic_links
    publication.sandbox.public_links = ['secret.txt']
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Fichiers interdits dans public (liens symboliques, fichiers spéciaux) : secret.txt'
    refute_includes log, 'Synchronisation simulée'
  end

  # Une compilation qui ne produit pas de site ne doit pas vider le site en ligne
  def test_refuses_site_without_index
    publication.sandbox.public_files = ['style.css']
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Site compilé incomplet : public/index.html manquant'
    refute_includes log, 'Synchronisation simulée'
  end

  def test_refuses_special_files
    publication.sandbox.public_fifos = ['bloque']
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Fichiers interdits dans public (liens symboliques, fichiers spéciaux) : bloque'
  end

  def test_exception
    publication.sandbox.error_to_raise = RuntimeError.new('boom')
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'RuntimeError: boom'
    assert_match(/^Fin : /, log)
  end

  def test_secrets_stay_private
    publication = Publication.new('universite', 'site', 'https://example.org/site.git', 'dxfl', { 'AWS_SECRET_ACCESS_KEY' => 'secret' })
    assert_raises(NoMethodError) { publication.variables }
  end
end
