require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.2.7'
require 'opentox-ruby-api-wrapper'

class Dataset
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	property :file, String, :length => 255
	#property :owl, Text, :length => 1000000
	property :created_at, DateTime

	def owl
		File.read self.file
	end

	def owl=(owl)
		self.file = File.join(File.dirname(File.expand_path(__FILE__)),'public',"#{id}.owl")
		File.open(self.file,"w+") { |f| f.write owl }
	end
end

DataMapper.auto_upgrade!

## REST API

get '/?' do
	Dataset.all.collect{|d| d.uri}.join("\n")
end

get '/:id/?' do
	begin
		dataset = Dataset.get(params[:id])
	rescue => e
		LOGGER.error e.message
		LOGGER.warn e.backtrace
		halt 404, "Dataset #{params[:id]} not found."
	end
	accept = request.env['HTTP_ACCEPT']
	accept = 'application/rdf+xml' if accept == '*/*' or accept == '' or accept.nil?
	case accept
	when /rdf/ # redland sends text/rdf instead of application/rdf+xml
		dataset.owl
	when /yaml/
		OpenTox::Dataset.find(dataset.uri).to_yaml
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
	task = OpenTox::Task.create
	pid = Spork.spork(:logger => LOGGER) do

		task.started
		LOGGER.debug "Dataset task #{task.uri} started"

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
		LOGGER.debug "Saving dataset #{uri}."
		begin
			dataset.owl = d.rdf
      dataset.uri = uri 
			dataset.save
			task.completed(uri) 
		rescue => e
			LOGGER.error e.message
			LOGGER.info e.backtrace
			halt 500, "Could not save dataset #{uri}."
		end
		LOGGER.debug "#{dataset.uri} saved."
	end
	task.pid = pid
	#status 303 # rest client tries to redirect
 	task.uri
  
  
  
  
end

delete '/:id/?' do
	begin
		dataset = Dataset.get(params[:id])
		File.delete dataset.file
		dataset.destroy!
		"Dataset #{params[:id]} deleted."
	rescue
		halt 404, "Dataset #{params[:id]} does not exist."
	end
end

delete '/?' do
  
	Dataset.all.each do |d|
		begin
			File.delete d.file 
		rescue
			LOGGER.error "Cannot delete dataset file '#{d.file}'"
		end
	 	#d.destroy!
	end
  Dataset.auto_migrate!
	"All datasets deleted."
end
