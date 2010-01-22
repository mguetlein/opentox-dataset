require 'rubygems'
gem 'opentox-ruby-api-wrapper', '~>1.2'
require 'opentox-ruby-api-wrapper'
require 'do_sqlite3'
require 'dm-core'
require 'dm-serializer'
require 'dm-timestamps'
require 'dm-types'

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/dataset.sqlite3")

class Dataset
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 100
	property :file, String
	property :owl, Text, :length => 1000000
	property :created_at, DateTime
end

DataMapper.auto_upgrade!

## REST API

get '/?' do
	Dataset.all.collect{|d| d.uri}.join("\n")
end

get '/:id/?' do
	dataset = Dataset.get(params[:id])
	halt 404, "Dataset #{uri} not found." unless dataset
	accept = request.env['HTTP_ACCEPT']
	accept = 'application/rdf+xml' if accept == '*/*' or accept == '' or accept.nil?
	case accept
	when /rdf/ # redland sends text/rdf instead of application/rdf+xml
		dataset.owl
	when /yaml/
		OpenTox::Dataset.find(uri).to_yaml
	else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
end

get '/:id/features/:feature_id/?' do
	OpenTox::Dataset.find(url_for("/#{params[:id]}", :full)).feature(params[:feature_id])
end

get '/:id/features/?' do
	OpenTox::Dataset.find(url_for("/#{params[:id]}", :full)).features
end

post '/?' do
	dataset = Dataset.new
	dataset.save
	uri = url_for("/#{dataset.id}", :full)
	content_type = request.content_type
	content_type = "application/rdf+xml" if content_type.nil?
	case request.content_type
	when "application/rdf+xml"
		rdf =	request.env["rack.input"].read
		d= OpenTox::Dataset.new
		d.rdf = rdf
		d.uri = uri
	else
		halt 404, "MIME type \"#{request.content_type}\" not supported."
	end
	dataset.owl = d.rdf
	dataset.uri = uri
	dataset.save
	print dataset.uri
	uri
end

delete '/:id/?' do
	begin
		Dataset.get(params[:id]).destroy!
		"Dataset #{params[:id]} deleted."
	rescue
		halt 404, "Dataset #{params[:id]} does not exist."
	end
end

delete '/?' do
	Dataset.all.each { |d| d.destroy! }
	"All datasets deleted."
end
