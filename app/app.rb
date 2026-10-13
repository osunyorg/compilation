require 'sinatra'
require 'sinatra/content_for'
require 'fileutils'
require 'json'
require 'base64'
require 'rbnacl'

REPOSITORIES_PATH = File.expand_path('../repositories', __dir__)
COMPILE_PATH = File.expand_path('../bin/compile', __dir__)
# Générés par bin/setup-keys, jamais versionnés
PRIVATE_KEY_PATH = File.expand_path('config/kelmscott.key', __dir__)
TOKEN_PATH = File.expand_path('config/kelmscott.token', __dir__)

# Liste blanche, identique à Communication::Website::Variable dans l'admin Osuny
KEYS_BY_SYNC_METHOD = {
  'sftp' => %w[SFTP_HOST SFTP_PORT SFTP_USER SFTP_PASSWORD SFTP_PATH],
  'dxfl' => %w[DXFL_USERNAME DXFL_PASSWORD DXFL_WEBSITE],
  'rsync' => %w[RSYNC_HOST RSYNC_PORT RSYNC_USER RSYNC_PATH RSYNC_SSH_PRIVATE_KEY],
  's3' => %w[S3_BUCKET S3_ENDPOINT S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY]
}.freeze
SECRET_KEYS = %w[SFTP_PASSWORD DXFL_PASSWORD RSYNC_SSH_PRIVATE_KEY AWS_SECRET_ACCESS_KEY].freeze

def directories_in(path)
  return [] unless File.directory?(path)
  Dir.children(path)
     .select { |name| File.directory?(File.join(path, name)) }
     .sort
end

# Lettres, chiffres, '_', '-' et '.', sans commencer par '.' (exclut '.', '..' et les dossiers cachés)
def valid_name?(name)
  name.match?(/\A[\w-][\w.-]*\z/)
end

def get_logs(university, site)
  path = "#{REPOSITORIES_PATH}/#{university}/#{site}/log.txt"
  return unless File.exist? path
  File.read path
end

def get_size(university, site)
  path = "#{REPOSITORIES_PATH}/#{university}/#{site}/**/*"
  Dir[path].select { |f| File.file?(f) }
           .sum { |f| File.size(f) }
end

def read_config(path)
  File.read(path).strip if File.exist?(path)
end

def authorized?
  token = read_config(TOKEN_PATH)
  return false if token.to_s.empty?
  provided = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
  Rack::Utils.secure_compare(token, provided)
end

# Les secrets sont chiffrés par l'admin avec la clé publique (sealed box libsodium)
def decrypt(value)
  private_key = RbNaCl::PrivateKey.new(Base64.strict_decode64(read_config(PRIVATE_KEY_PATH)))
  RbNaCl::Boxes::Sealed.from_private_key(private_key).decrypt(Base64.strict_decode64(value))
end

def fetch_repository(repository_path, git_url)
  if File.directory?(repository_path)
    system('git', '-C', repository_path, 'pull') &&
      system('git', '-C', repository_path, 'submodule', 'update', '--init', '--recursive')
  else
    system('git', 'clone', '--recurse-submodules', '--', git_url, repository_path)
  end
end

def publish(university, site, git_url, environment)
  repository_path = File.join(REPOSITORIES_PATH, university, site)
  FileUtils.mkdir_p(File.dirname(repository_path))
  # Un seul build à la fois par site, y compris entre workers Puma
  File.open("#{repository_path}.lock", File::CREAT) do |lock|
    lock.flock(File::LOCK_EX)
    return warn("[#{university}/#{site}] Récupération du dépôt impossible") unless fetch_repository(repository_path, git_url)
    # Les secrets ne sont pas transmis à la compilation, qui exécute du code du dépôt (yarn install)
    return warn("[#{university}/#{site}] Échec de la compilation") unless system(COMPILE_PATH, repository_path)
    # TODO: synchronisation avec `environment` (variables et secrets déchiffrés)
  end
rescue StandardError => e
  warn "[#{university}/#{site}] #{e.class}: #{e.message}"
end

get '/' do
  @title = 'Kelmscott'
  @universities = directories_in(REPOSITORIES_PATH)
  erb :index
end

get '/:university' do
  @university = params[:university]
  @title = @university
  path = REPOSITORIES_PATH + '/' + @university
  @sites = directories_in(path)
  erb :university
end

get '/:university/:site' do
  @university = params[:university]
  @site = params[:site]
  @size = get_size(@university, @site)
  @title = @site
  @logs = get_logs(@university, @site)
  erb :site
end

post '/:university/:site' do
  halt 503, 'Kelmscott keys are not configured' unless File.exist?(PRIVATE_KEY_PATH) && File.exist?(TOKEN_PATH)
  halt 401, 'Unauthorized' unless authorized?

  university = params[:university]
  site = params[:site]
  halt 400, 'Invalid university' unless valid_name?(university)
  halt 400, 'Invalid site' unless valid_name?(site)

  halt 415, 'Content-Type must be application/json' unless request.media_type == 'application/json'
  payload = JSON.parse(request.body.read) rescue halt(400, 'Invalid JSON')
  halt 400, 'Invalid JSON' unless payload.is_a?(Hash)

  git_url = payload['git_url'].to_s
  halt 400, 'Invalid git_url' unless git_url.start_with?('https://')

  sync_method = payload['sync_method'].to_s
  halt 400, 'Invalid sync_method' unless KEYS_BY_SYNC_METHOD.key?(sync_method)

  variables = payload['variables'] || {}
  halt 400, 'Invalid variables' unless variables.is_a?(Hash) && variables.values.all?(String)
  unknown_keys = variables.keys - KEYS_BY_SYNC_METHOD[sync_method]
  halt 400, "Unknown variables: #{unknown_keys.join(', ')}" if unknown_keys.any?

  begin
    secrets = variables.slice(*SECRET_KEYS).transform_values { |value| decrypt(value) }
  rescue ArgumentError, RbNaCl::CryptoError
    halt 400, 'Secret decryption failed'
  end
  environment = variables.merge(secrets)

  Thread.new { publish(university, site, git_url, environment) }
  status 202
  'Accepted'
end
