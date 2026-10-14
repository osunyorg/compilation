require_relative 'test_helper'

class PublicationTest < KelmscottTest
  # Remplace le sandbox et la synchronisation, qui ne tournent que sur le serveur
  class FakePublication < Publication
    attr_accessor :fetch_result, :compile_result, :sync_result, :public_files, :public_links, :site_files, :error_to_raise

    def initialize(*)
      super
      @fetch_result = true
      @compile_result = true
      @sync_result = true
      @public_files = ['index.html']
      @public_links = []
      # Chemin dans le dossier du site => taille en Mo
      @site_files = {}
    end

    private

    def build(command, *)
      raise error_to_raise if error_to_raise
      return fetch_result if command == 'fetch'
      public_path = File.join(repository_path, 'public')
      FileUtils.mkdir_p(public_path)
      public_files.each { |file| File.write(File.join(public_path, file), 'ok') }
      public_links.each { |link| File.symlink('/etc/hosts', File.join(public_path, link)) }
      site_files.each do |file, megabytes|
        path = File.join(site_path, file)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, 'x' * megabytes * 1024**2)
      end
      execute('echo', 'Compilation simulée')
      compile_result
    end

    def sync
      execute('echo', 'Synchronisation simulée')
      sync_result
    end

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
      assert_match(/^#{step} : \d+ s$/, log)
    end
    assert_match(/^Fin : /, log)
    assert_match(/^Durée totale : /, log)
    assert_match(/^Poids : \d+ Mo$/, log)
  end

  def test_size_details
    publication.site_files = {
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
    publication.fetch_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Récupération du dépôt impossible'
    refute_match(/^Compilation : /, log)
    assert_match(/^Fin : /, log)
  end

  def test_compile_failure
    publication.compile_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Échec de la compilation'
    refute_includes log, 'Synchronisation simulée'
    refute_match(/^Synchronisation : /, log)
  end

  def test_sync_failure
    publication.sync_result = false
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Échec de la synchronisation'
    assert_match(/^Synchronisation : /, log)
  end

  def test_refuses_symbolic_links
    publication.public_links = ['secret.txt']
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'Liens symboliques interdits dans public : secret.txt'
    refute_includes log, 'Synchronisation simulée'
  end

  def test_exception
    publication.error_to_raise = RuntimeError.new('boom')
    publication.run
    assert_equal 'failure', status
    assert_includes log, 'RuntimeError: boom'
    assert_match(/^Fin : /, log)
  end

  def test_secrets_stay_private
    publication = Publication.new('universite', 'site', 'https://example.org/site.git', 'dxfl', { 'AWS_SECRET_ACCESS_KEY' => 'secret' })
    assert_raises(NoMethodError) { publication.environment }
  end
end
