require 'sinatra'
require 'sinatra/content_for'

get '/' do
  erb :index
end

get '/sites/:id/' do
  erb :show
end

post '/sites/:id/' do
  system "create #{params[:id]}"
  erb :show
end

patch '/sites/:id/' do
  system "compile #{params[:id]}"
  erb :show
end
