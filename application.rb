require 'rubygems'
require 'opentox-ruby-api-wrapper'
require File.join File.dirname(__FILE__), 'redis', 'dataset.rb'

set :default_content, :yaml

helpers do

	def find
		uri = uri(params[:splat].first)
		halt 404, "Dataset \"#{uri}\" not found." unless @set = Dataset.find(uri)
	end

	def uri(name)
		name = URI.encode(name)
		uri = url_for("/", :full) + name
	end

end

## REST API

get '/?' do
	Dataset.find_all.join("\n")
end

get '/*/name/?' do
	find
	URI.decode(URI.split(@set.uri)[5].split(/\//)[1])
end

get '/*/features/?' do
	find
	@set.features.join("\n")
end

get '/*/compounds/?' do
	find
	@set.compounds.join("\n")
end

get '/*/compound/*/?' do
	find
	inchi = params[:splat][1]#.gsub(/(InChI.*) (.*)/,'\1+\2')) # reinsert dropped '+' signs in InChIs
	@set.compound_features(inchi).join("\n")
end

# catch the rest
get '/*/?' do
	find
	dataset = {}
	@set.compounds.each do |c|
		dataset[c] = @set.compound_features(c)
	end
	dataset.to_yaml
end

# create a dataset
post '/?' do
	dataset_uri = uri(params[:name])
	halt 403, "Dataset \"#{dataset_uri}\" exists." if Dataset.find(dataset_uri)
	Dataset.create(dataset_uri).uri
end

put '/*/import/?' do
	find
	halt 404, "Compound format #{params[:compound_format]} not (yet) supported" unless params[:compound_format] =~ /smiles|inchi|name/
	#task = OpenTox::Task.create(@set.uri)
	data = {}
	case	params[:file][:type]
	when "text/csv"
		File.open(params[:file][:tempfile].path).each_line do |line|
			record = line.chomp.split(/,\s*/)
			compound_uri = OpenTox::Compound.new(:smiles => record[0]).uri
#			begin
			feature_uri = OpenTox::Feature.new(:name => @set.name, :classification => record[1]).uri
#			rescue
#				puts "Error: " + line
#				puts record.join("\t")
#				puts @set.name.to_s
#				#puts [record[0] , @set.name , record[1]].to_yaml
#			end
			data[compound_uri] = [] unless data[compound_uri]
			data[compound_uri] << feature_uri
		end
	else
		halt 404, "File format #{request.content_type} not (yet) supported"
	end
	@set.add(data.to_yaml)
	@set.uri
end

# import yaml
put '/*/?' do
	find
	@set.add(params[:features])
end

delete '/*/?' do
	find
	@set.delete
end
