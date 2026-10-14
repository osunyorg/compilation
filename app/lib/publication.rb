require 'base64'
require 'fileutils'
require 'rbnacl'
require_relative 'formats'

# Récupération, compilation et synchronisation d'un site, exécutées en arrière-plan
class Publication
  include Formats

  # Chaque étape tourne dans le sandbox (sandbox/run) : la récupération et la compilation, qui exécutent
  # du code du dépôt, sous kelmscott-build ; la synchronisation, qui reçoit les secrets, sous kelmscott-sync
  SANDBOX_PATH = '/usr/local/sbin/kelmscott-sandbox'
  # Un dossier par site, écrit par le build
  SITES_PATH = '/srv/kelmscott/sites'
  # Logs, statuts et verrous, écrits par le service, invisibles depuis le sandbox
  STATE_PATH = '/srv/kelmscott/state'

  # Liste blanche, identique à Communication::Website::Variable dans l'admin Osuny
  # Chaque méthode correspond à un script dans sync/, installé par bin/steps/sandbox
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
                      :variables,
                      :durations,
                      :started_at

  # Fichier d'état d'un site (log, status, size, lock), lu aussi par l'interface web
  def self.state_file(university, site, extension)
    File.join(STATE_PATH, university, "#{site}.#{extension}")
  end

  # Une publication du site est en cours : son verrou est pris
  def self.running?(university, site)
    path = state_file(university, site, 'lock')
    return false unless File.exist?(path)
    File.open(path) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }
  end

  # Les secrets sont chiffrés par l'admin avec la clé publique de Kelmscott (sealed box libsodium)
  def self.decrypt(value)
    private_key = RbNaCl::PrivateKey.new(Base64.strict_decode64(File.read(Helpers::PRIVATE_KEY_PATH).strip))
    RbNaCl::Boxes::Sealed.from_private_key(private_key).decrypt(Base64.strict_decode64(value))
  end

  # Les variables arrivent telles que reçues de l'admin : les secrets sont déchiffrés au dernier moment,
  # en mémoire, pour la synchronisation
  def initialize(university, site, git_url, sync_method, variables)
    @university = university
    @site = site
    @git_url = git_url
    @sync_method = sync_method
    @variables = variables
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

  def log_path
    @log_path ||= self.class.state_file(university, site, 'log')
  end

  def status_path
    @status_path ||= self.class.state_file(university, site, 'status')
  end

  # Espace disque du site, additionné sur l'accueil
  def size_path
    @size_path ||= self.class.state_file(university, site, 'size')
  end

  # Un seul build à la fois par site, y compris entre workers Puma
  def lock
    lock_path = self.class.state_file(university, site, 'lock')
    FileUtils.mkdir_p(File.dirname(lock_path))
    File.open(lock_path, File::CREAT) do |file|
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

  # Seuls des fichiers et des dossiers ordinaires sont mis en ligne : un lien symbolique publierait un fichier
  # du serveur, et un fichier spécial (FIFO…) bloquerait la synchronisation
  def publishable
    public_path = File.join(repository_path, 'public')
    forbidden = Dir.glob('**/*', File::FNM_DOTMATCH, base: public_path).reject do |path|
      %w[file directory].include?(File.lstat(File.join(public_path, path)).ftype)
    end
    forbidden.empty? || error("Fichiers interdits dans public (liens symboliques, fichiers spéciaux) : #{forbidden.join(', ')}")
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
    lines << "Durée : #{format_duration(finished_at - started_at)}"
    lines += durations.map { |name, duration| "  #{name} : #{format_duration(duration)}" }
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

  # Les variables passent par l'entrée standard : ni par les arguments (visibles dans ps),
  # ni par l'environnement de l'unité systemd (visible dans systemctl show)
  def sync
    execute('sudo', '--non-interactive', SANDBOX_PATH, 'sync', university, site, sync_method, input: sync_input)
  end

  # Une variable par ligne, NOM=valeur en base 64, lue par sandbox/sync. Les secrets sont déchiffrés ici.
  def sync_input
    variables.map do |name, value|
      value = self.class.decrypt(value) if SECRET_KEYS.include?(name)
      "#{name}=#{Base64.strict_encode64(value)}\n"
    end.join
  end

  def execute(*command, input: nil)
    return system(*command, out: [log_path, 'a'], err: [:child, :out]) if input.nil?
    IO.popen(command, 'w', out: [log_path, 'a'], err: [:child, :out]) do |io|
      io.write(input)
    rescue Errno::EPIPE
      # Le processus s'est arrêté sans tout lire : son code de sortie le dit
    end
    $?.success?
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
