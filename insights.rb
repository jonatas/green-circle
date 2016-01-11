load './go.rb'

require "sinatra"
require "pp"
require "chartkick"

get "/" do
	r
  erb :insights
end

get "/static/:file" do
  file = "./views/static/#{params[:file]}"
  send_file(file)
end

{
  "Total successful builds" => Build.count,

}.each do |title, code|
  puts "# #{title}","","","```ruby"
  pp code
  puts "```","",""
end
