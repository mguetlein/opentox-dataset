## SETUP
[ 'rubygems', 'sinatra', 'sinatra/url_for', 'dm-core', 'dm-more', 'builder', 'opentox-ruby-api-wrapper' ].each do |lib|
	require lib
end

## MODELS

class Dataset
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :finished, Boolean, :default => false
	has n, :associations
end

class Association
	include DataMapper::Resource
	property :id, Serial
	property :compound_uri, String, :size => 255
	property :feature_uri, String, :size => 255
	belongs_to :dataset
end

sqlite = "#{File.expand_path(File.dirname(__FILE__))}/#{Sinatra::Base.environment}.sqlite3"
DataMapper.setup(:default, "sqlite3:///#{sqlite}")
DataMapper::Logger.new(STDOUT, 0)

unless FileTest.exists?("#{sqlite}")
	[Dataset, Association].each do |model|
		model.auto_migrate!
	end
end

## REST API

get '/?' do
	Dataset.all.collect{ |d| url_for("/", :full) + d.id.to_s }.join("\n")
end

get '/:id' do
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	halt 202, dataset.to_yaml  unless dataset.finished
	dataset.to_yaml
=begin
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
=end
end

get '/:id/name' do
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	dataset.name
end

get '/:id/compounds' do
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	dataset.associations.collect{ |a| a.compound_uri }.uniq.join("\n")
end

get '/:id/features' do
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	dataset.associations.collect{ |a| a.feature_uri }.uniq.join("\n")
end

get '/:id/features/compounds' do

	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])

	features = {}
	dataset.associations.each do |a|
		if features[a.feature_uri]
			features[a.feature_uri] << a.compound_uri
		else
			features[a.feature_uri] = [a.compound_uri]
		end
	end
	features.to_yaml

=begin
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
=end
end

get '/:id/compounds/features' do

	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	compounds = {}
	dataset.associations.each do |a|
		if compounds[a.compound_uri]
			compounds[a.compound_uri] << a.feature_uri
		else
			compounds[a.compound_uri] = [a.feature_uri]
		end
	end
	compounds.to_yaml
=begin
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
=end
end

get '/:id/compound/*/features' do 
	compound_uri = params[:splat].first
	Association.all(:dataset_id => params[:id], :compound_uri => compound_uri).collect { |a| a.feature_uri }.uniq.join("\n")
end

get '/:id/feature/*/compounds' do 
	feature_uri = params[:splat].first
	Association.all(:dataset_id => params[:id], :feature_uri => feature_uri).collect { |a| a.compound_uri }.uniq.join("\n")
end

post '/?' do
	#protected!
	dataset = Dataset.create :name => params[:name]

	if params[:file]
		Spork.spork do
			File.open(params[:file][:tempfile].path).each_line do |line|
				record = line.chomp.split(/,\s*/)
				compound = OpenTox::Compound.new :smiles => record[0]
				feature = OpenTox::Feature.new :name => params[:name], :values => { 'classification' => record[1] }
				Association.create(:compound_uri => compound.uri, :feature_uri => feature.uri, :dataset_id => dataset.id)
			end
			dataset.update_attributes(:finished => true)
		end

=begin
	elsif params[:data]
		puts params[:data]
		dataset = Dataset.create :name => params[:name]
		#Spork.spork do
			YAML.load(params[:data]).each do |record|
				compound = OpenTox::Compound.new :uri => record[0]
				feature = OpenTox::Feature.new :uri => record[1] 
				puts compound + "\t" , feature
				Association.create(:compound_uri => compound.uri, :feature_uri => feature.uri, :dataset_id => dataset.id)
			end
			dataset.update_attributes(:finished => true)
		#end
=end
	end
	url_for("/", :full) + dataset.id.to_s
end

put '/:id' do
	#protected!
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	compound_uri =  params[:compound_uri]
	feature_uri = params[:feature_uri] 
	Association.create(:compound_uri => compound_uri.to_s, :feature_uri => feature_uri.to_s, :dataset_id => dataset.id)
	url_for("/", :full) + dataset.id.to_s
end

put '/:id/finished' do
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	dataset.update_attributes(:finished => true)
end

delete '/:id' do
	# dangerous, because other datasets might refer to it
	#protected!
	halt 404, "Dataset #{params[:id]} not found." unless dataset = Dataset.get(params[:id])
	dataset.associations.each { |a| a.destroy }
	dataset.destroy
	"Successfully deleted dataset #{params[:id]}."
end
