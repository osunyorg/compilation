require 'sinatra'
require 'sinatra/content_for'

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

post '/sites/:id/' do
  system "bin/clone #{params[:id]}"
  erb :show
end

patch '/sites/:id/' do
  system "bin/compile #{params[:id]}"
  erb :show
end
