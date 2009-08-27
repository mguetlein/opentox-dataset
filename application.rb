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

helpers do

	def create_dataset(uri)
		@@redis.set_add "datasets", uri
	end

	def	add_feature(dataset_uri, compound_uri, feature_uri)
		@@redis.set_add dataset_uri + '::compounds', compound_uri
		@@redis.set_add dataset_uri + '::features', feature_uri
		@@redis.set_add dataset_uri + '::' + compound_uri + '::features', feature_uri
		@@redis.set_add dataset_uri + '::' + feature_uri + '::compounds', compound_uri
	end

	def delete_dataset(uri)
		@@redis.set_members(uri + '::compounds').each do |compound_uri|
			@@redis.delete uri + '::' + compound_uri
		end
		@@redis.delete uri + '::compounds'
		@@redis.set_members(uri + '::features').each do |feature_uri|
			@@redis.delete uri + '::' + feature_uri
		end
		@@redis.delete uri + '::features'
		@@redis.set_delete "datasets", uri
	end

	def not_found?
		halt 404, "Dataset \"#{params[:name]}\" not found." unless @@redis.set_member? "datasets", uri(params[:name])
	end

	def uri(name)
		uri = url_for("/", :full) + name.gsub(/\s|\n/,'_')
	end

end

## REST API

get '/?' do
	@@redis.set_members("datasets").collect{|d| uri(d)}.join("\n")
end

get '/:name' do
  not_found?
  @dataset = {:uri => uri(params[:name]), :name => params[:name]}
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
  @@redis.set_members(uri(params[:name]) + "::compounds").join("\n")
end

get '/:name/features' do
  not_found?
  @@redis.set_members(uri(params[:name]) + "::features").join("\n")
end

=begin
get '/:name/:type/*/*/intersection' do
  # CHECK/TEST
  @@redis.set_intersect(params[:splat][0], params[:splat][1], URI.encode(params[:name]) + '/' + params[:type]).join("\n")
end

get '/:name/:type/*/*/union' do
  # CHECK/TEST
  @@redis.set_union(params[:splat][0], params[:splat][1], URI.encode(params[:name]) + '/' + params[:type]).join("\n")
end
=end

get '/:name/*/features' do 
	not_found?
	# re-escape smiles (Sinatra unescapes params and splats)
	compound_uri = params[:splat].first.sub(%r{(http://[\w\.:]+/)(.*)$}) {|s| $1 + URI.escape($2, /[^#{URI::PATTERN::UNRESERVED}]/)}
	
	#puts compound_uri
  @@redis.set_members(uri(params[:name]) + '::' + compound_uri + '::features').join("\n")
end

get '/:name/*/compounds' do 
	not_found?
  @@redis.set_members(uri(params[:name]) + '::' + params[:splat].first + '::compounds').join("\n")
end

post '/?' do
  #protected!
	uri = uri(params[:name])
  halt 403, "Dataset \"#{name}\" exists - please choose another name." if @@redis.set_member?("datasets", uri)

  @@redis.set_add "datasets", uri

  if params[:file]
		File.open(params[:file][:tempfile].path).each_line do |line|
			record = line.chomp.split(/,\s*/)
			compound_uri = OpenTox::Compound.new(:smiles => record[0]).uri
			feature_uri = OpenTox::Feature.new(:name => params[:name], :values => {:classification => record[1]}).uri
			add_feature(uri, compound_uri, feature_uri)
		end
  end
	uri
end

put '/:name/?' do
  #protected!
  not_found?
	uri = uri(params[:name])
	add_feature(uri, params[:compound_uri],params[:feature_uri])
  uri + " sucessfully updated."
end

delete '/:name/?' do
  # dangerous, because other datasets might refer to it
  #protected!
  not_found?
	uri = uri(params[:name])
	delete_dataset(uri)
  "Successfully deleted dataset \"#{uri}\"."
end
