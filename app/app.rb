require 'sinatra'
require 'sinatra/content_for'
require 'fileutils'

REPOSITORIES_PATH = File.expand_path('../repositories', __dir__)

get '/' do
  @repositories = Dir.children(REPOSITORIES_PATH)
                     .select { |name| File.directory?(File.join(REPOSITORIES_PATH, name)) }
                     .sort
  erb :index
end

get '/sites/:id/' do
  erb :show
end

patch '/sites/:university_slug/:site_id/compile' do
  # TODO: il faut vérifier que university_slug et site_id ne soient pas malveillants (ex: ne commencent pas par '.' ou ne contiennent pas de caractères spéciaux)
  halt 400, 'Missing gitpath' if params[:gitpath].to_s.empty?

  repository_path = File.join(REPOSITORIES_PATH, params[:university_slug], params[:site_id])
  if File.directory?(repository_path)
    pulled = system('git', '-C', repository_path, 'pull')
    halt 500, 'Pull failed' unless pulled
  else
    FileUtils.mkdir_p(REPOSITORIES_PATH)
    cloned = system('git', 'clone', '--', params[:gitpath], repository_path)
    halt 500, 'Clone failed' unless cloned
  end

  system "bin/compile #{params[:university_slug]} #{params[:site_id]}"
  erb :show
end
