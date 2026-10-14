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
  @summary = 'Imprimerie de sites web'
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
  halt 409, 'Request already received' unless first_use?

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

  halt 503, 'Too many publications, retry later' unless Publication.reserve
  Thread.new do
    Publication.new(university, site, git_url, sync_method, environment).run
  ensure
    Publication.release
  end
  status 202
  'Accepted'
end
