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

class Dataset

	include OpenTox::Utils
	attr_reader :uri, :name

	def initialize(uri)
		@name = File.basename(uri)
		@uri = uri
	end

	def self.create(uri)
		dataset = Dataset.new(uri)
		dataset.save
		dataset
	end

	def self.find(uri)
		if @@redis.set_member? "datasets", uri
			Dataset.new(uri)
		else
			nil
		end
	end

	def self.exists?(uri)
		@@redis.set_member? "datasets", uri
	end

	def self.find_all_uris
		@@redis.set_members("datasets")
	end

	def save
		@@redis.set_add "datasets", uri
	end

	def destroy
		@@redis.set_members(@uri + '::compounds').each do |compound_uri|
			@@redis.delete @uri + '::' + compound_uri
		end
		@@redis.delete @uri + '::compounds'
		@@redis.set_members(@uri + '::features').each do |feature_uri|
			@@redis.delete @uri + '::' + feature_uri
		end
		@@redis.delete @uri + '::features'
		@@redis.set_delete "datasets", @uri
	end

	def add(compound_uri,feature_uri)
		@@redis.set_add @uri + '::compounds', compound_uri
		@@redis.set_add @uri + '::features', feature_uri
		@@redis.set_add @uri + '::' + compound_uri + '::features', feature_uri
		@@redis.set_add @uri + '::' + feature_uri + '::compounds', compound_uri
	end

	def compound_uris
		@@redis.set_members(@uri + "::compounds")
	end

	def feature_uris
		@@redis.set_members(@uri + "::features")
	end

	def feature_uris_for_compound(compound_uri)
		@@redis.set_members(@uri + '::' + compound_uri + '::features')
	end
	 
	def compound_uris_for_feature(feature_uri)
		@@redis.set_members(@uri + '::' + feature_uri + '::compounds')
	end

	def tanimoto(compound_uris)
		raise "Exactly 2 compounds are needed for similarity calculations" unless compound_uris.size == 2
		compound_keys = compound_uris.collect{ |c| @uri + '::' + c + "::features" }
		union_size = @@redis.set_union(compound_keys[0], compound_keys[1]).size
		intersect_size = @@redis.set_intersect(compound_keys[0], compound_keys[1]).size
		intersect_size.to_f/union_size.to_f
	end

	def weighted_tanimoto(compound_uris)
		raise "Exactly 2 compounds are needed for similarity calculations" unless compound_uris.size == 2
		compound_keys = compound_uris.collect{ |c| @uri + '::' + c + "::features" }
		union = @@redis.set_union(compound_keys[0], compound_keys[1])
		intersect = @@redis.set_intersect(compound_keys[0], compound_keys[1])

		p_sum_union = 0.0
		p_sum_intersect = 0.0

		union.each{ |f| p_sum_union += gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		intersect.each{ |f| p_sum_intersect += gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		"#{p_sum_intersect/p_sum_union}"
	end

end

helpers do

	def not_found?
		halt 404, "Dataset \"#{params[:name]}\" not found." unless Dataset.exists? uri(params[:name])
	end

	def uri(name)
		uri = url_for("/", :full) + name.gsub(/\s|\n/,'_')
	end

end

## REST API

get '/?' do
	Dataset.find_all_uris.join("\n")
end

get '/:name' do
  not_found?
	@dataset = Dataset.find(uri params[:name])
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
  Dataset.find(uri params[:name]).compound_uris.join("\n")
end

get '/:name/features' do
  not_found?
  Dataset.find(uri params[:name]).feature_uris.join("\n")
end

get '/:name/compound/*/features' do 
	not_found?
	compound_uri = params[:splat].first.gsub(/ /,'+')
	Dataset.find(uri params[:name]).feature_uris_for_compound(compound_uri).join("\n")
end

get '/:name/feature/*/compounds' do 
	not_found?
	Dataset.find(uri params[:name]).compound_uris_for_feature(params[:splat].first).join("\n")
end

get '/:name/tanimoto/compound/*/compound/*/?' do 
	not_found?
	compound_uris = params[:splat].collect{ |c| c.gsub(/ /,'+') }
	"#{Dataset.find(uri params[:name]).tanimoto(compound_uris)}"
end

get '/:name/weighted_tanimoto/compound/*/compound/*/?' do 
	not_found?
	compound_uris = params[:splat].collect{ |c| c.gsub(/ /,'+') }
	Dataset.find(uri params[:name]).weighted_tanimoto(compound_uris)
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
	dataset = Dataset.find(uri params[:name])
	dataset.add(params[:compound_uri],params[:feature_uri])
  dataset.uri + " sucessfully updated."
end

delete '/:name/?' do
  # dangerous, because other datasets might refer to it
  #protected!
  not_found?
	Dataset.find(uri params[:name]).destroy
  "Successfully deleted dataset \"#{params[:name]}\"."
end
