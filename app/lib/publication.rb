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

  private attr_reader :university,
                      :site,
                      :git_url,
                      :sync_method,
                      :environment,
                      :durations,
                      :started_at

  def initialize(university, site, git_url, sync_method, environment)
    @university = university
    @site = site
    @git_url = git_url
    @sync_method = sync_method
    @environment = environment
    @durations = {}
  end

  def run
    lock do
      start
      fetched && compiled && synced && succeeded
    ensure
      finish
    end
  rescue StandardError => e
    error "#{e.class}: #{e.message}"
  end

  private

  def repository_path
    @repository_path ||= File.join(REPOSITORIES_PATH, university, site)
  end

  def log_path
    @log_path ||= File.join(repository_path, 'log.txt')
  end

  def status_path
    @status_path ||= "#{repository_path}.status"
  end

  # Un seul build à la fois par site, y compris entre workers Puma
  def lock
    FileUtils.mkdir_p(File.dirname(repository_path))
    File.open("#{repository_path}.lock", File::CREAT) do |file|
      file.flock(File::LOCK_EX)
      yield
    end
  end

  def start
    @started_at = Time.now
    File.write(status_path, 'building')
  end

  def fetched
    return error('Récupération du dépôt impossible') unless step('Récupération') { fetch_repository }
    # Écrit après le clone, qui exige un dossier vide
    File.write(log_path, "Début : #{format_time(started_at)}\n\n")
    @log_started = true
  end

  def compiled
    step('Compilation') { compile } || error('Échec de la compilation')
  end

  def synced
    step('Synchronisation') { sync } || error('Échec de la synchronisation')
  end

  def succeeded
    File.write(status_path, 'success')
  end

  # Récapitulatif en fin de log, même en cas d'échec
  def finish
    return unless @log_started
    File.write(log_path, summary, mode: 'a')
  end

  def summary
    finished_at = Time.now
    lines = ['', "Fin : #{format_time(finished_at)}"]
    lines += durations.map { |name, duration| "#{name} : #{format_duration(duration)}" }
    lines << "Durée totale : #{format_duration(finished_at - started_at)}"
    lines << "Poids : #{format_size(size_of(repository_path))}"
    lines.join("\n") + "\n"
  end

  # Mesure la durée d'une étape, y compris en cas d'échec, pour le récapitulatif du log
  def step(name)
    step_started_at = Time.now
    yield
  ensure
    durations[name] = Time.now - step_started_at
  end

  # Clones superficiels : seul le dernier commit est conservé, sans reflog pour que
  # le gc automatique de git puisse supprimer les anciens commits
  def fetch_repository
    if File.directory?(repository_path)
      system('git', '-C', repository_path, 'config', 'core.logAllRefUpdates', 'false') &&
        system('git', '-C', repository_path, 'fetch', '--depth', '1') &&
        system('git', '-C', repository_path, 'reset', '--hard', '@{upstream}') &&
        system('git', '-C', repository_path, 'submodule', 'update', '--init', '--recursive', '--depth', '1', '--force')
    else
      system('git', 'clone', '--depth', '1', '--recurse-submodules', '--shallow-submodules', '--', git_url, repository_path)
    end
  end

  # Les secrets ne sont pas transmis à la compilation, qui exécute du code du dépôt (yarn install)
  def compile
    system(COMPILE_PATH, repository_path)
  end

  def sync
    system(environment, File.join(SYNC_PATH, sync_method), repository_path,
           out: [log_path, 'a'], err: [:child, :out])
  end

  def error(message)
    File.write(status_path, 'failure')
    warn "[#{university}/#{site}] #{message}"
    false
  end

  def format_time(time)
    time.strftime('%d/%m/%Y %H:%M:%S %Z')
  end

  # Fichiers du dépôt, hors dossiers cachés (.git)
  def size_of(path)
    Dir["#{path}/**/*"].select { |file| File.file?(file) }
                       .sum { |file| File.size(file) }
  end

  def format_size(bytes)
    "#{bytes / 1024 / 1024} Mo"
  end

  def format_duration(seconds)
    minutes, seconds = seconds.round.divmod(60)
    minutes.zero? ? "#{seconds} s" : "#{minutes} min #{seconds} s"
  end
end
