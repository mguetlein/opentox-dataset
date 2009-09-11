# SETUP
[ 'rubygems', 'redis', 'opentox-ruby-api-wrapper' ].each do |lib|
  require lib
end

case ENV['RACK_ENV']
when 'production'
  @@redis = Redis.new :db => 0
when 'development'
  @@redis = Redis.new :db => 1
when 'test'
  @@redis = Redis.new :db => 2
  @@redis.flush_db
end

load File.join(File.dirname(__FILE__), 'dataset.rb')

set :default_content, :yaml

helpers do

	def find
		# + charges are dropped
		uri = uri(params[:splat].first.gsub(/(InChI.*) (.*)/,'\1+\2')) # reinsert dropped '+' signs in InChIs
		#puts uri
		halt 404, "Dataset \"#{uri}\" not found." unless @set = Dataset.find(uri)
	end

	def uri(name)
=begin
		if name =~ /InChI/
			name = URI.encode(name,/[^#{URI::PATTERN::UNRESERVED}]/)
		else
			name = URI.encode(name)
		end
=end
		name = URI.encode(name)
		uri = url_for("/dataset/", :full) + name
	end

end

## REST API

load 'compound.rb'
load 'feature.rb'

get '/datasets/?' do
	Dataset.find_all.join("\n")
end

get '/algorithm/tanimoto/dataset/*/dataset/*/?' do
	find
	@set.tanimoto(uri(params[:splat][1]))
end


get '/algorithm/weighted_tanimoto/dataset/*/dataset/*/?' do
	find
	@set.weighted_tanimoto(uri(params[:splat][1]))
end

get '/dataset/*/name/?' do
	find
	URI.decode @set.name
end

get '/dataset/*/features/?' do
	find
	@set.features.join("\n")
end

# catch the rest
get '/dataset/*/?' do
	find
	@set.members.join("\n")
end

# create a dataset
post '/datasets/?' do
	dataset_uri = uri(params[:name])
	halt 403, "Dataset \"#{dataset_uri}\" exists." if Dataset.find(dataset_uri)
	@set = Dataset.create(dataset_uri)
	@set.add Dataset.create(File.join(dataset_uri, "compounds")).uri
	@set.add Dataset.create(File.join(dataset_uri, "features")).uri
	@set.uri
end

load 'import.rb'

# import yaml
post '/dataset/*/?' do
	find
	@compounds_set = Dataset.find File.join(@set.uri, "compounds")
	@features_set = Dataset.find File.join(@set.uri, "features")
	YAML.load(params[:features]).each do |compound_uri,feature_uris|
		# key: /dataset/:dataset/compound/:inchi
		@compound_features = Dataset.find_or_create File.join(@set.uri,'compound',OpenTox::Compound.new(:uri => compound_uri).inchi)
		feature_uris.each do |feature_uri|
			@compounds_set.add compound_uri
			@features_set.add feature_uri
			@compound_features.add feature_uri
		end
  end
	@set.uri
end

delete '/dataset/*/?' do
	find
	@set.members.each{|m| Dataset.find(m).delete} if @set.members
	@set.delete
end
