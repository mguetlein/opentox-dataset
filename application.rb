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

	def not_found?
		halt 404, "Dataset \"#{params[:name]}\" not found." unless @dataset = Dataset.find(uri(params[:name]))
	end

	def uri(name)
		uri = url_for("/", :full) + name.gsub(/\s|\n/,'_')
	end

end

=begin
# current sinatra version does not halt in before filter, should be resolved in future versions
before do
	if params[:name] and !request.post?
		halt 404, "Dataset \"#{params[:name]}\" not found." unless @dataset = Dataset.find(url_for("/", :full) + name.gsub(/\s|\n/,'_'))
	end
end
=end

## REST API

get '/?' do
	Dataset.find_all.join("\n")
end

get '/:name' do
  not_found?
  respond_to do |format|
    format.yaml { @dataset.to_yaml }
    format.xml {  builder :dataset }
  end
end

get '/:name/name' do
  not_found?
  URI.decode(params[:name])
end

get '/:name/compounds' do
  not_found?
  @dataset.compound_uris.join("\n")
end

get '/:name/features' do
  not_found?
  @dataset.feature_uris.join("\n")
end

get '/:name/compound/*/features' do 
	not_found?
	compound_uri = params[:splat].first.gsub(/ /,'+')
	@dataset.feature_uris_for_compound(compound_uri).join("\n")
end

get '/:name/feature/*/compounds' do 
	not_found?
	@dataset.compound_uris_for_feature(params[:splat].first).join("\n")
end

get '/tanimoto/:name0/compound/*/:name1/compound/*/?' do 
	compound_uris = params[:splat].collect{ |c| c.gsub(/ /,'+') }
	features = [ {:dataset_uri => uri(params[:name0]), :compound_uri => compound_uris[0]}, {:dataset_uri => uri(params[:name1]), :compound_uri => compound_uris[1]} ]
	"#{Dataset.tanimoto(features)}"
end

get '/weighted_tanimoto/:name0/compound/*/:name1/compound/*/?' do 
	compound_uris = params[:splat].collect{ |c| c.gsub(/ /,'+') }
	features = [ {:dataset_uri => uri(params[:name0]), :compound_uri => compound_uris[0]}, {:dataset_uri => uri(params[:name1]), :compound_uri => compound_uris[1]} ]
	Dataset.weighted_tanimoto(features)
end

post '/?' do
  #protected!
  halt 403, "Dataset \"#{name}\" exists - please choose another name." if Dataset.exists?(uri params[:name])

	dataset = Dataset.create(uri params[:name])

  if params[:file]
		File.open(params[:file][:tempfile].path).each_line do |line|
			record = line.chomp.split(/,\s*/)
			compound_uri = OpenTox::Compound.new(:smiles => record[0]).uri
			feature_uri = OpenTox::Feature.new(:name => params[:name], :values => {:classification => record[1]}).uri
			dataset.add(compound_uri, feature_uri)
		end
  end
	dataset.uri
end

put '/:name/?' do
  #protected!
  not_found?
	@dataset.add(params[:compound_uri],params[:feature_uri])
  @dataset.uri + " sucessfully updated."
end

delete '/:name/?' do
  #protected!
  not_found?
	@dataset.destroy
  "Successfully deleted dataset \"#{params[:name]}\"."
end

# Dataset collections
get '/collections/?' do
	DatasetCollection.find_all.join("\n")
end

get '/collection/:name/?' do
	@collection = DatasetCollection.find(uri params[:name])
  respond_to do |format|
    format.yaml { @collection.to_yaml }
    format.xml {  builder :collection }
  end
end

post '/collections/?' do
  halt 403, "Dataset collection \"#{name}\" exists - please choose another name." if DatasetCollection.exists?(uri params[:name])
	DatasetCollection.create(uri params[:name], :dataset_uris => params[:datasets]).uri
end

delete '/collection/:name/?' do
	DatasetCollection.find(uri params[:name]).destroy
  "Successfully deleted dataset collection \"#{params[:name]}\"."
end
