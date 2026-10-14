require 'sinatra'
require 'sinatra/content_for'
require 'json'
require_relative 'lib/formats'
require_relative 'lib/helpers'
require_relative 'lib/publication'

helpers Helpers, Formats

# Les noms (URL) et les logs (sortie du build, contrôlée par le dépôt du site) sont affichés dans les pages
set :erb, escape_html: true

get '/' do
  @title = 'Kelmscott'
  @summary = 'Kelmscott est une imprimerie de sites web. La Kelmscott Press représente l’aboutissement de la carrière de William Morris dans le domaine des arts graphiques, où il peut réaliser d’un bout à l’autre ses aspirations et mettre en application ses principes. Le nom vient du village de Kelmscott, où il a acquis le manoir du même nom. Morris aspire à retrouver le métier des anciens typographes, la prééminence du travail manuel sur la mécanisation et l’industrialisation. Dans un laps de temps relativement court, entre 1891 et 1898 (Morris disparaît en 1896), la Kelmscott Press produit 66 livres, inspirés par les incunables des premières années de l’imprimerie. C’est ce que nous essayons de réaliser avec osuny : une publication artisanale de sites web.'
  @universities = directories_in(Publication::SITES_PATH)
  @used_space = used_space
  @free_space, @total_space = disk_space
  erb :index
end

get '/:university' do
  halt 400 unless valid_name?(params[:university])
  @university = params[:university]
  @title = @university
  path = File.join(Publication::SITES_PATH, @university)
  @sites = directories_in(path)
  erb :university
end

get '/:university/:site' do
  halt 400 unless valid_name?(params[:university]) && valid_name?(params[:site])
  @university = params[:university]
  @site = params[:site]
  @title = @site
  @logs = get_logs(@university, @site)
  @status = get_status(@university, @site)
  erb :site
end

# Public : affiché par l'admin Osuny, comme le badge d'un workflow GitHub
get '/:university/:site/badge.svg' do
  halt 400 unless valid_name?(params[:university]) && valid_name?(params[:site])
  @text, @color = badge(get_status(params[:university], params[:site]))
  content_type 'image/svg+xml'
  cache_control :no_cache
  erb :'badge.svg', layout: false
end

post '/:university/:site' do
  halt 503, 'Kelmscott keys are not configured' unless configured?
  # Sinatra a pu lire le corps pour remplir params (formulaire) : on le relit depuis le début
  request.body.rewind
  body = request.body.read
  halt 401, 'Unauthorized' unless signed?(body)

  university = params[:university]
  site = params[:site]
  halt 400, 'Invalid university' unless valid_name?(university)
  halt 400, 'Invalid site' unless valid_name?(site)

  halt 415, 'Content-Type must be application/json' unless request.media_type == 'application/json'
  payload = JSON.parse(body) rescue halt(400, 'Invalid JSON')
  halt 400, 'Invalid JSON' unless payload.is_a?(Hash)

  git_url = payload['git_url'].to_s
  halt 400, 'Invalid git_url' unless valid_git_url?(git_url)

  sync_method = payload['sync_method'].to_s
  halt 400, 'Invalid sync_method' unless Publication::KEYS_BY_SYNC_METHOD.key?(sync_method)

  variables = payload['variables'] || {}
  halt 400, 'Invalid variables' unless variables.is_a?(Hash) && variables.values.all?(String)
  unknown_keys = variables.keys - Publication::KEYS_BY_SYNC_METHOD[sync_method]
  halt 400, "Unknown variables: #{unknown_keys.join(', ')}" if unknown_keys.any?

  begin
    secrets = variables.slice(*Publication::SECRET_KEYS).transform_values { |value| decrypt(value) }
  rescue ArgumentError, RbNaCl::CryptoError
    halt 400, 'Secret decryption failed'
  end
  environment = variables.merge(secrets)

  Thread.new { Publication.new(university, site, git_url, sync_method, environment).run }
  status 202
  'Accepted'
end
