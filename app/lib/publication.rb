require 'fileutils'

# Récupération, compilation et synchronisation d'un site, exécutées en arrière-plan
class Publication
  REPOSITORIES_PATH = File.expand_path('../../repositories', __dir__)
  COMPILE_PATH = File.expand_path('../../bin/compile', __dir__)
  SYNC_PATH = File.expand_path('../../bin/sync', __dir__)

  # Liste blanche, identique à Communication::Website::Variable dans l'admin Osuny
  # Chaque méthode correspond à un script dans bin/sync
  KEYS_BY_SYNC_METHOD = {
    'sftp' => %w[SFTP_HOST SFTP_PORT SFTP_USER SFTP_PASSWORD SFTP_PATH],
    'dxfl' => %w[DXFL_BUCKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY],
    'rsync' => %w[RSYNC_HOST RSYNC_PORT RSYNC_USER RSYNC_PATH RSYNC_SSH_PRIVATE_KEY],
    's3' => %w[S3_BUCKET S3_ENDPOINT S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY]
  }.freeze
  SECRET_KEYS = %w[SFTP_PASSWORD RSYNC_SSH_PRIVATE_KEY AWS_SECRET_ACCESS_KEY].freeze

  def initialize(university, site, git_url, sync_method, environment)
    @university = university
    @site = site
    @git_url = git_url
    @sync_method = sync_method
    @environment = environment
    @repository_path = File.join(REPOSITORIES_PATH, university, site)
    @log_path = File.join(@repository_path, 'log.txt')
  end

  def run
    FileUtils.mkdir_p(File.dirname(@repository_path))
    # Un seul build à la fois par site, y compris entre workers Puma
    File.open("#{@repository_path}.lock", File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      started_at = Time.now
      return error('Récupération du dépôt impossible') unless fetch_repository
      # Écrit après le clone, qui exige un dossier vide
      File.write(@log_path, "Début : #{format_time(started_at)}\n\n")
      begin
        return error('Échec de la compilation') unless compile
        return error('Échec de la synchronisation') unless sync
      ensure
        finished_at = Time.now
        File.write(@log_path, "\nFin : #{format_time(finished_at)}\nDurée : #{format_duration(finished_at - started_at)}\n", mode: 'a')
      end
    end
  rescue StandardError => e
    error "#{e.class}: #{e.message}"
  end

  private

  def fetch_repository
    if File.directory?(@repository_path)
      system('git', '-C', @repository_path, 'pull') &&
        system('git', '-C', @repository_path, 'submodule', 'update', '--init', '--recursive')
    else
      system('git', 'clone', '--recurse-submodules', '--', @git_url, @repository_path)
    end
  end

  # Les secrets ne sont pas transmis à la compilation, qui exécute du code du dépôt (yarn install)
  def compile
    system(COMPILE_PATH, @repository_path)
  end

  def sync
    system(@environment, File.join(SYNC_PATH, @sync_method), @repository_path,
           out: [@log_path, 'a'], err: [:child, :out])
  end

  def error(message)
    warn "[#{@university}/#{@site}] #{message}"
  end

  def format_time(time)
    time.strftime('%d/%m/%Y %H:%M:%S %Z')
  end

  def format_duration(seconds)
    minutes, seconds = seconds.round.divmod(60)
    minutes.zero? ? "#{seconds} s" : "#{minutes} min #{seconds} s"
  end
end
