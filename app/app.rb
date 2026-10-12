require 'sinatra'
require 'sinatra/content_for'
require 'fileutils'

REPOSITORIES_PATH = File.expand_path('../repositories', __dir__)
COMPILE_PATH = File.expand_path('../bin/compile', __dir__)

get '/' do
  @repositories = Dir.children(REPOSITORIES_PATH)
                     .select { |name| File.directory?(File.join(REPOSITORIES_PATH, name)) }
                     .sort
  erb :index
end

get '/sites/:university_slug/' do
  erb :university
end

get '/sites/:university_slug/:site_id' do
  erb :site
end

patch '/sites/:university_slug/:site_id/compile' do
  # TODO: il faut vérifier que university_slug et site_id ne soient pas malveillants (ex: ne commencent pas par '.' ou ne contiennent pas de caractères spéciaux)
  # TODO: il faut remplacer les halt par des logs (ou faire les 2)
  halt 400, 'Missing gitpath' if params[:gitpath].to_s.empty?

  repository_path = File.join(REPOSITORIES_PATH, params[:university_slug], params[:site_id])
  if File.directory?(repository_path)
    pulled = system('git', '-C', repository_path, 'pull') &&
             system('git', '-C', repository_path, 'submodule', 'update', '--init', '--recursive')
    halt 500, 'Pull failed' unless pulled
  else
    FileUtils.mkdir_p(REPOSITORIES_PATH)
    cloned = system('git', 'clone', '--recurse-submodules', '--', params[:gitpath], repository_path)
    halt 500, 'Clone failed' unless cloned
  end

  compiled = system(COMPILE_PATH, repository_path)
  halt 500, 'Compilation failed' unless compiled
  erb :show
end
