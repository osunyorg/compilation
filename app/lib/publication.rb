require 'fileutils'
require_relative 'formats'

# Récupération, compilation et synchronisation d'un site, exécutées en arrière-plan
class Publication
  include Formats

  # La récupération et la compilation, qui exécutent du code du dépôt,
  # tournent dans le sandbox (sandbox/run), sous l'utilisateur kelmscott-build
  SANDBOX_PATH = '/usr/local/sbin/kelmscott-sandbox'
  # Un dossier par site, écrit par le build
  SITES_PATH = '/srv/kelmscott/sites'
  # Logs, statuts et verrous, écrits par le service, invisibles depuis le sandbox
  STATE_PATH = '/srv/kelmscott/state'
  SYNC_PATH = File.expand_path('../../sync', __dir__)

  # Liste blanche, identique à Communication::Website::Variable dans l'admin Osuny
  # Chaque méthode correspond à un script dans sync/
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
      fetched && compiled && publishable && synced && succeeded
    ensure
      finish
    end
  rescue StandardError => e
    error "#{e.class}: #{e.message}"
  end

  private

  def site_path
    @site_path ||= File.join(SITES_PATH, university, site)
  end

  def repository_path
    @repository_path ||= File.join(site_path, 'repository')
  end

  def state_path
    @state_path ||= File.join(STATE_PATH, university)
  end

  def log_path
    @log_path ||= File.join(state_path, "#{site}.log")
  end

  def status_path
    @status_path ||= File.join(state_path, "#{site}.status")
  end

  # Espace disque du site, additionné sur l'accueil
  def size_path
    @size_path ||= File.join(state_path, "#{site}.size")
  end

  # Un seul build à la fois par site, y compris entre workers Puma
  def lock
    FileUtils.mkdir_p(state_path)
    File.open(File.join(state_path, "#{site}.lock"), File::CREAT) do |file|
      file.flock(File::LOCK_EX)
      yield
    end
  end

  def start
    @started_at = Time.now
    File.write(status_path, 'building')
    File.write(log_path, "Début : #{format_time(started_at)}\n\n")
  end

  def fetched
    step('Récupération') { build('fetch', git_url) } || error('Récupération du dépôt impossible')
  end

  def compiled
    step('Compilation') { build('compile') } || error('Échec de la compilation')
  end

  # Un lien symbolique dans public/ ferait mettre en ligne un fichier du serveur, lu par le service
  def publishable
    public_path = File.join(repository_path, 'public')
    links = Dir.glob('**/*', File::FNM_DOTMATCH, base: public_path).select { |path| File.symlink?(File.join(public_path, path)) }
    links.empty? || error("Liens symboliques interdits dans public : #{links.join(', ')}")
  end

  def synced
    step('Synchronisation') { sync } || error('Échec de la synchronisation')
  end

  def succeeded
    File.write(status_path, 'success')
  end

  # Récapitulatif en fin de log, même en cas d'échec
  def finish
    size = disk_usage(site_path)
    File.write(size_path, size)
    File.write(log_path, summary(size), mode: 'a')
  end

  def summary(size)
    finished_at = Time.now
    lines = ['', "Fin : #{format_time(finished_at)}"]
    lines += durations.map { |name, duration| "#{name} : #{format_duration(duration)}" }
    lines << "Durée totale : #{format_duration(finished_at - started_at)}"
    lines << "Poids : #{format_size(size)}"
    lines += size_details(size).map { |name, bytes| "  #{name} : #{format_size(bytes)}" }
    lines.join("\n") + "\n"
  end

  # Détail du poids : les morceaux mesurés, et par différence les sources du dépôt et les caches du build
  # (node_modules n'est qu'un lien vers la toolchain partagée)
  def size_details(size)
    repository = disk_usage(repository_path)
    details = {
      'Site compilé (public)' => disk_usage(File.join(repository_path, 'public')),
      'Historique git (.git)' => disk_usage(File.join(repository_path, '.git'))
    }
    details['Sources'] = repository - details.values.sum
    details['Caches'] = size - repository
    details
  end

  # Mesure la durée d'une étape, y compris en cas d'échec, pour le récapitulatif du log
  def step(name)
    step_started_at = Time.now
    yield
  ensure
    durations[name] = Time.now - step_started_at
  end

  # sandbox/fetch et sandbox/compile exécutent du code du dépôt, sans les secrets
  def build(command, *arguments)
    execute('sudo', '--non-interactive', SANDBOX_PATH, command, university, site, *arguments)
  end

  # Hors sandbox, sous l'utilisateur du service : seul code à recevoir les secrets
  def sync
    execute(environment, File.join(SYNC_PATH, sync_method), repository_path)
  end

  def execute(*command)
    system(*command, out: [log_path, 'a'], err: [:child, :out])
  end

  def error(message)
    File.write(status_path, 'failure')
    File.write(log_path, "\n#{message}\n", mode: 'a') if File.exist?(log_path)
    warn "[#{university}/#{site}] #{message}"
    false
  end

  # Espace disque réel d'un dossier, en octets (0 s'il n'existe pas)
  def disk_usage(path)
    IO.popen(['du', '-sk', path], err: File::NULL, &:read).to_i * 1024
  end
end
