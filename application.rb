require 'rubygems'
require 'opentox-ruby-api-wrapper'

mime :rdf, "application/rdf+xml"
set :default_content, :rdf

## REST API

get '/?' do
	Dir["datasets/*"].collect{|dataset|  url_for("/", :full) + File.basename(dataset,".rdf")}.sort.join("\n")
end

get '/:id/?' do
	send_file File.join("datasets",params[:id] + ".rdf")
end

get '/:id/features/?' do

	storage = Redland::MemoryStore.new
	parser = Redland::Parser.new
	data = Redland::Model.new storage
	rdf = File.read File.join(File.dirname(__FILE__),"datasets","#{params[:id]}.rdf")
	parser.parse_string_into_model(data,rdf,Redland::Uri.new('/'))

	features = []
	data.triples { |s,p,o| features << p.uri.to_s }
	features.uniq.join("\n")
end

post '/?' do
	case request.content_type
	when"application/rdf+xml"
		input =	request.env["rack.input"].read
		id = Dir["datasets/*"].collect{|dataset|  File.basename(dataset,".rdf").to_i}.sort.last
		if id.nil?
			id = 1
		else
			id += 1
		end
		File.open(File.join("datasets",id.to_s + ".rdf"),"w+") { |f| f.write input }
		url_for("/#{id}", :full)
	else
		"MIME type \"#{request.content_type}\" not supported."
	end
end

put '/:id/?' do
	case request.content_type
	when"application/rdf+xml"
		input =	request.env["rack.input"].read
		id = params[:id]
		File.delete(File.join("datasets",id.to_s + ".rdf"))
		File.open(File.join("datasets",id.to_s + ".rdf"),"w+") { |f| f.write input }
		url_for("/#{id}", :full)
	else
		"MIME type \"#{request.content_type}\" not supported."
	end
end

delete '/:id/?' do
	path = File.join("datasets",params[:id] + ".rdf")
	if File.exists? path
		File.delete path
		"Dataset #{params[:id]} deleted."
	else
		status 404
		"Dataset #{params[:id]} does not exist."
	end
end

delete '/?' do
	Dir["datasets/*rdf"].each do |f|
		File.delete f
	end
	"All datasets deleted."
end
