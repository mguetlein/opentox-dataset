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

	def not_found?
		halt 404, "Dataset \"#{params[:name]}\" not found." unless @@redis.set_member? "datasets", sanitize_key(params[:name])
	end

	def sanitize_key(k)
		k.gsub(/\s|\n/,'_')
	end

	def name(uri)
		URI.decode File.basename(uri)
	end

	def uri(name)
		uri = url_for("/", :full) + URI.escape(URI.unescape(name)) # avoid escaping escaped names
	end

	def	add_feature(name, record)
		compound = record[0]
		feature = record[1] 
		@@redis.set_add name + '::compounds', compound
		@@redis.set_add name + '::features', name + '::' + feature
		@@redis.set_add compound, name + '::' + feature
		@@redis.set_add feature, compound
	end

	def delete_dataset(name)
		# stale features/compounds under compound and name::feature ??
		@@redis.delete name + '::compounds'
		@@redis.delete name + '::features'
		@@redis.set_delete "datasets", name
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
  @@redis.set_members(URI.encode(params[:name]) + "::compounds").join("\n")
end

get '/:name/features' do
  not_found?
  @@redis.set_members(URI.encode(params[:name]) + "::features").join("\n")
end

get '/:name/:type/*/*/intersection' do
  # CHECK/TEST
  @@redis.set_intersect(params[:splat][0], params[:splat][1], URI.encode(params[:name]) + '/' + params[:type]).join("\n")
end

get '/:name/:type/*/*/union' do
  # CHECK/TEST
  @@redis.set_union(params[:splat][0], params[:splat][1], URI.encode(params[:name]) + '/' + params[:type]).join("\n")
end

get '/:name/*/features' do 
  compound = URI.encode(params[:splat].first, /[^#{URI::PATTERN::UNRESERVED}]/)
  @@redis.set_intersect(params[:name] + '::features', compound ).join("\n")
  @@redis.set_intersect(params[:name] + '::features', compound ).join("\n")
end

get '/:name/*/compounds' do 
  feature = params[:splat].first
  @@redis.set_intersect(feature, params[:name] + '::compounds').join("\n")
end

post '/?' do
  #protected!
	name = sanitize_key params[:name]
  halt 403, "Dataset \"#{name}\" exists - please choose another name." if @@redis.set_member?("datasets", name)

  @@redis.set_add "datasets", name

  if params[:file]
		File.open(params[:file][:tempfile].path).each_line do |line|
			record = line.chomp.split(/,\s*/)
			add_feature(name, record)
		end
  end
	uri name 
end

put '/:name/?' do
  #protected!
  pass if params[:finished]
  not_found?
	name = sanitize_key params[:name]
  compound =  params[:compound]
  feature = sanitize_key params[:feature] 
	add_feature(name, [compound,feature])
  name + " sucessfully updated."
end

delete '/:name/?' do
  # dangerous, because other datasets might refer to it
  #protected!
  not_found?
  name = sanitize_key params[:name]
	delete_dataset(name)
  "Successfully deleted dataset \"#{name}\"."
end
