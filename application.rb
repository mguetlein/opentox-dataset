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

set :default_content, :yaml
load File.join(File.dirname(__FILE__), 'dataset.rb')

helpers do

	def find
		uri = uri(params[:splat].first)
		halt 404, "Dataset \"#{uri}\" not found." unless @set = Dataset.find(uri)
	end

	def uri(name)
		uri = url_for("/dataset/", :full) + URI.encode(name)
	end

end

## REST API

load 'compound.rb'
load 'feature.rb'

get '/datasets/?' do
	Dataset.find_all.join("\n")
end

get '/dataset/*/tanimoto/*/?' do
	find
	@set.tanimoto(uri(params[:splat][1]))
end

get '/dataset/*/weighted_tanimoto/*/?' do
	find
	@set.weighted_tanimoto(uri(params[:splat][1]))
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
	@set.uri
end

load 'import.rb'

# import yaml
post '/dataset/*/?' do
	find
	@compounds_set = Dataset.find File.join(@set.uri, "compounds")
	YAML.load(params[:features]).each do |compound_uri,feature_uris|
		# key: /dataset/:dataset/compound/:inchi/:feature_type
		@compound_features = Dataset.find_or_create File.join(@set.uri,'compound',OpenTox::Compound.new(:uri => compound_uri).inchi,URI.escape(params[:feature_type]))
		feature_uris.each do |feature_uri|
			@compounds_set.add compound_uri
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
