require 'sinatra'
require 'sinatra/content_for'
require 'fileutils'

REPOSITORIES_PATH = File.expand_path('../repositories', __dir__)
COMPILE_PATH = File.expand_path('../bin/compile', __dir__)

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

patch '/:university/:site/compile' do
  @university = params[:university]
  @site = params[:site]
  @title = @site

  # TODO: il faut remplacer les halt par des logs (ou faire les 2)
  halt 400, 'Invalid university' unless valid_name?(@university)
  halt 400, 'Invalid site' unless valid_name?(@site)
  halt 400, 'Missing git_url' if params[:git_url].to_s.empty?

  repository_path = File.join(REPOSITORIES_PATH, @university, @site)
  if File.directory?(repository_path)
    pulled = system('git', '-C', repository_path, 'pull') &&
             system('git', '-C', repository_path, 'submodule', 'update', '--init', '--recursive')
    halt 500, 'Pull failed' unless pulled
  else
    FileUtils.mkdir_p(REPOSITORIES_PATH)
    cloned = system('git', 'clone', '--recurse-submodules', '--', params[:git_url], repository_path)
    halt 500, 'Clone failed' unless cloned
  end

  compiled = system(COMPILE_PATH, repository_path)
  halt 500, 'Compilation failed' unless compiled
  erb :site
end
