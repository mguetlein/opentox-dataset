## SETUP
[ 'rubygems', 'sinatra', 'rest_client', 'sinatra/url_for', 'datamapper', 'dm-more', 'do_sqlite3', 'builder', 'api_key' ].each do |lib|
	require lib
end

# reload

## MODELS

class Dataset
	include DataMapper::Resource
	property :id, Serial
	property :name, String, :unique => true
	has n, :associations
end

class Association
	include DataMapper::Resource
	property :id, Serial
	property :compound_uri, Text
	property :feature_uri, Text
	belongs_to :dataset
end

# automatically create the tables
configure :test do 
	DataMapper.setup(:default, 'sqlite3::memory:')
	[Dataset, Association].each do |model|
		model.auto_migrate!
	end
end

@db = "datasets.sqlite3"
configure :development, :production do
	DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/#{@db}")
	unless FileTest.exists?("#{@db}")
		[Dataset, Association].each do |model|
			model.auto_migrate!
		end
	end
	puts @db
end

# configure services
COMPOUNDS_SERVICE_URI = "http://webservices.in-silico.ch/compounds/"
FEATURES_SERVICE_URI = "http://webservices.in-silico.ch/features/"

## Authentification
helpers do

  def protected!
    response['WWW-Authenticate'] = %(Basic realm="Testing HTTP Auth") and \
    throw(:halt, [401, "Not authorized\n"]) and \
    return unless authorized?
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['api', API_KEY]
  end

end

## REST API
get '/' do
	Dataset.all.collect{ |d| url_for("/", :full) + d.id.to_s }.join("\n")
end

get '/:id' do
	begin
		dataset = Dataset.get(params[:id])
		builder do |xml|
			xml.instruct!
			xml.dataset do
				xml.uri url_for("/", :full) + dataset.id.to_s
				xml.name dataset.name
				dataset.associations.each do |a|
					xml.association do
						xml.compound a.compound_uri
						xml.feature a.feature_uri
					end
				end
			end
		end
	rescue
		status 404
		"Cannot find dataset with ID #{params[:id]}."
	end
end

put '/:id' do
	begin
		dataset = Dataset.get params[:id]
		compound_uri = RestClient.post COMPOUNDS_SERVICE_URI, :name => params[:compound_name]
		feature_uri = RestClient.post FEATURES_SERVICE_URI, :name => params[:feature_name], :value => params[:feature_value]
		Association.create(:compound_uri => compound_uri.to_s, :feature_uri => feature_uri.to_s, :dataset_id => dataset.id)
		url_for("/", :full) + dataset.id.to_s
	rescue
		status 500
		"Failed to update dataset #{params[:id]}."
	end
end

post '/' do
	protected!
	begin
		dataset = Dataset.create :name => params[:dataset_name]
		url_for("/", :full) + dataset.id.to_s
	rescue
		status 500
		"Failed to create new dataset."
	end
end

delete '/:id' do
	# dangerous, because other datasets might refer to it
	protected!
	begin
		dataset = Dataset.get(params[:id])
		dataset.associations.each { |a| a.destroy }
		dataset.destroy
		"Successfully deleted dataset #{params[:id]}."
	rescue
		status 500
		"Can not delete dataset #{params[:id]}."
	end
end
