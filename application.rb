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

get '/:id/features/:feature_id/?' do
	OpenTox::Dataset.find(url_for("/#{params[:id]}", :full)).feature(params[:feature_id])
end

get '/:id/features/?' do
	OpenTox::Dataset.find(url_for("/#{params[:id]}", :full)).features
end

post '/?' do
	id = Dir["datasets/*"].collect{|dataset|  File.basename(dataset,".rdf").to_i}.sort.last
	id = id.nil? ? 1 : id + 1
	uri = url_for("/#{id}", :full)
	content_type = request.content_type
	content_type = "application/rdf+xml" if content_type.nil?
	case request.content_type
=begin
		when /yaml/
			File.open(File.join("datasets",id.to_s + ".rdf"),"w+") { |f| f.write model.to_string }
			url_for("/#{id}", :full)
=end
	when "application/rdf+xml"
		rdf =	request.env["rack.input"].read
		dataset = OpenTox::Dataset.new
		dataset.rdf = rdf
		dataset.uri = uri
	else
		halt 404, "MIME type \"#{request.content_type}\" not supported."
	end
	File.open(File.join("datasets",id.to_s + ".rdf"),"w+") { |f| f.write dataset.rdf }
	uri
end

=begin
put '/:id/?' do
	uri = url_for("/#{params[:id]}", :full)
	id = params[:id]
	uri =	url_for("/#{id}", :full)
	case request.content_type
	when "application/rdf+xml"
		input =	request.env["rack.input"].read
		storage = Redland::MemoryStore.new
		parser = Redland::Parser.new
		model = Redland::Model.new storage
		parser.parse_string_into_model(model,input,Redland::Uri.new('/'))
		dataset = model.subject RDF['type'], OT["Dataset"]
		identifier = model.object(dataset, DC['identifier'])
		model.delete dataset, DC['identifier'], identifier
		model.add dataset, DC['identifier'], uri
		File.delete(File.join("datasets",id.to_s + ".rdf"))
		File.open(File.join("datasets",id.to_s + ".rdf"),"w+") { |f| f.write model.to_string }
	else
		halt 404, "MIME type \"#{request.content_type}\" not supported."
	end
end
=end

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
