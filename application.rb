## SETUP
[ 'rubygems', 'sinatra', 'sinatra/url_for', 'datamapper', 'dm-more', 'builder', 'api_key' ].each do |lib|
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
	property :compound_uri, URI
	property :feature_uri, URI
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
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	builder do |xml|
		xml.instruct!
		xml.dataset do
			xml.uri url_for("/", :full) + dataset.id.to_s
			xml.name dataset.name
			dataset.associations.each do |a|
				xml.association do
					xml.compound_uri a.compound_uri
					xml.feature_uri a.feature_uri
				end
			end
		end
	end
end

get '/:id/name' do
	begin
		Dataset.get(params[:id]).name
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
end

get '/:id/compounds' do
	begin
		Dataset.get(params[:id]).associations.collect{ |a| a.compound_uri }.uniq.join("\n")
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
end

get '/:id/features' do
	begin
		Dataset.get(params[:id]).associations.collect{ |a| a.feature_uri }.uniq.join("\n")
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
end

get '/:id/features/compounds' do

	begin
		dataset = Dataset.get(params[:id])
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	features = {}
	dataset.associations.each do |a|
		if features[a.feature_uri]
			features[a.feature_uri] << a.compound_uri
		else
			features[a.feature_uri] = [a.compound_uri]
		end
	end

	builder do |xml|
		xml.instruct!
		xml.dataset do
			features.each do |feature,compounds|
				xml.feature do
					xml.uri feature
					compounds.each do |c|
						xml.compound_uri c
					end
				end
			end
		end
	end
end

get '/:id/compounds/features' do

	begin
		dataset = Dataset.get(params[:id])
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	compounds = {}
	dataset.associations.each do |a|
		if compounds[a.compound_uri]
			compounds[a.compound_uri] << a.feature_uri
		else
			compounds[a.compound_uri] = [a.feature_uri]
		end
	end

	builder do |xml|
		xml.instruct!
		xml.dataset do
			compounds.each do |compound,features|
				xml.compound do
					xml.uri compound
					features.each do |f|
						xml.feature_uri f
					end
				end
			end
		end
	end
end

get '/:id/compound/*/features' do 
	compound_uri = params[:splat].first
	Association.all(:dataset_id => params[:id], :compound_uri => compound_uri).collect { |a| a.feature_uri }.uniq.join("\n")
end

get '/:id/feature/*/compounds' do 
	feature_uri = params[:splat].first
	Association.all(:dataset_id => params[:id], :feature_uri => feature_uri).collect { |a| a.compound_uri }.uniq.join("\n")
end

post '/' do
	protected!
	dataset = Dataset.find_or_create :name => params[:name]
	url_for("/", :full) + dataset.id.to_s
end

post '/:id' do
	protected!
	begin
		dataset = Dataset.get params[:id]
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	compound_uri =  params[:compound_uri]
	feature_uri = params[:feature_uri] 
	Association.create(:compound_uri => compound_uri.to_s, :feature_uri => feature_uri.to_s, :dataset_id => dataset.id)
	url_for("/", :full) + dataset.id.to_s
end

delete '/:id' do
	# dangerous, because other datasets might refer to it
	protected!
	begin
		dataset = Dataset.get params[:id]
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	dataset.associations.each { |a| a.destroy }
	dataset.destroy
	"Successfully deleted dataset #{params[:id]}."
end

delete '/:id/associations' do
	protected!
	begin
		dataset = Dataset.get params[:id]
	rescue
		status 404
		"Dataset #{params[:id]} not found."
	end
	dataset.associations.each { |a| a.destroy }
	"Associations for dataset #{params[:id]} successfully deleted."
end
