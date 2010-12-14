require 'rubygems'
gem "opentox-ruby", "~> 0"
require 'opentox-ruby'

class Dataset

  include DataMapper::Resource
  property :id, Serial
  property :uri, String, :length => 255
  property :yaml, Text, :length => 2**32-1 
  property :created_at, DateTime

  attr_accessor :token_id
  @token_id = nil
  
  after :save, :check_policy

  def load(params,request)

    data = request.env["rack.input"].read
    content_type = request.content_type
    content_type = "application/rdf+xml" if content_type.nil?
    dataset = OpenTox::Dataset.new
    
    case content_type

    when /yaml/
      dataset.load_yaml(data)

    when "application/rdf+xml"
      dataset.load_rdfxml(data)

    when /multipart\/form-data/ , "application/x-www-form-urlencoded" # file uploads

      case params[:file][:type]

      when /yaml/
        dataset.load_yaml(params[:file][:tempfile].read)

      when "application/rdf+xml"
        dataset.load_rdfxml_file(params[:file][:tempfile])

      when "text/csv"
        dataset = OpenTox::Dataset.new @uri
        dataset.load_csv(params[:file][:tempfile].read)
        dataset.add_metadata({
          DC.title => File.basename(params[:file][:filename],".csv"),
          OT.hasSource => File.basename(params[:file][:filename])
        })

      when /ms-excel/
        extension =  File.extname(params[:file][:filename])
        case extension
        when ".xls"
          xls = params[:file][:tempfile].path + ".xls"
          File.rename params[:file][:tempfile].path, xls # roo needs these endings
          book = Excel.new xls
        when ".xlsx"
          xlsx = params[:file][:tempfile].path + ".xlsx"
          File.rename params[:file][:tempfile].path, xlsx # roo needs these endings
          book = Excel.new xlsx
        else
          raise "#{params[:file][:filename]} is not a valid Excel input file."
        end
        dataset.load_spreadsheet(book)
        dataset.add_metadata({
          DC.title => File.basename(params[:file][:filename],extension),
          OT.hasSource => File.basename(params[:file][:filename])
        })

      else
        raise "MIME type \"#{params[:file][:type]}\" not supported."
      end

    else
      raise "MIME type \"#{content_type}\" not supported."
    end

    dataset.uri = @uri # update uri (also in metdata)
    dataset.features.keys.each { |f| dataset.features[f][OT.hasSource] = dataset.metadata[OT.hasSource] unless dataset.features[f][OT.hasSource]}
    update(:yaml => dataset.to_yaml)
  end

=begin
  def create_representations
    dataset = YAML.load yaml
    ["rdfxml","xls"].each do |extension|
      file = "public/#{@id}.#{extension}"
      FileUtils.rm Dir["public/#{file}"] if File.exists? file
      File.open(file,"w+") { |f| f.puts eval("dataset.to_#{extension}") }
    end
  end
=end

  private
  def check_policy
    OpenTox::Authorization.check_policy(uri, token_id)
  end

end

DataMapper.auto_upgrade!

before do
  @accept = request.env['HTTP_ACCEPT']
  @accept = 'application/rdf+xml' if @accept == '*/*' or @accept == '' or @accept.nil?
end

## REST API

# Get a list of available datasets
# @return [text/uri-list] List of available datasets
get '/?' do
  response['Content-Type'] = 'text/uri-list'
  Dataset.all(params).collect{|d| d.uri}.join("\n") + "\n"
end

# Get a dataset representation
# @param [Header] Accept one of `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` (default application/rdf+xml)
# @return [application/rdf+xml, application-x-yaml, text/csv, application/ms-excel] Dataset representation
get '/:id' do

  extension = File.extname(params[:id]).sub(/\./,'')
  unless extension.empty?
    params[:id].sub!(/\.#{extension}$/,'')
    case extension
    when "yaml"
      @accept = 'application/x-yaml'
    when "csv"
      @accept = 'text/csv'
    when "rdfxml"
      @accept = 'application/rdf+xml'
    when "xls"
      @accept = 'application/ms-excel'
    else
      halt 404, "File format #{extension} not supported."
    end
  end

  dataset = OpenTox::Dataset.new
  dataset.load_yaml(Dataset.get(params[:id]).yaml)
  halt 404, "Dataset #{params[:id]} empty." if dataset.nil? # not sure how an empty dataset can be returned, but if this happens stale processes keep runing at 100% cpu
  
  case @accept

  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    file = "public/#{params[:id]}.rdfxml"
    File.open(file,"w+") { |f| f.puts dataset.to_rdfxml } unless File.exists? file # lazy rdfxml generation
    response['Content-Type'] = 'application/rdf+xml'
    File.open(file).read

  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    dataset.to_yaml
 
  when "text/csv"
    response['Content-Type'] = 'text/csv'
    dataset.to_csv

  when /ms-excel/
    file = "public/#{params[:id]}.xls"
    dataset.to_xls.write(file) unless File.exists? file # lazy xls generation
    response['Content-Type'] = 'application/ms-excel'
    File.open(file).read

  else
    halt 404, "Content-type #{@accept} not supported."
  end
end

# Get metadata of the dataset
# @return [application/rdf+xml] Metadata OWL-DL
get '/:id/metadata' do

  metadata = YAML.load(Dataset.get(params[:id]).yaml).metadata
  
  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_metadata url_for("/#{params[:id]}",:full), metadata
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

# Get a dataset feature
# @param [Header] Accept one of `application/rdf+xml or application-x-yaml` (default application/rdf+xml)
# @return [application/rdf+xml,application/x-yaml] Feature metadata 
get %r{/(\d+)/feature/(.*)$} do |id,feature|
#get '/:id/feature/:feature_name/?' do 

  #feature_uri = url_for("/#{params[:id]}/feature/#{URI.encode(params[:feature_name])}",:full) # work around  racks internal uri decoding 
  #dataset = YAML.load(Dataset.get(params[:id]).yaml)
  feature_uri = url_for("/#{id}/feature/#{URI.encode(feature)}",:full) # work around  racks internal uri decoding 
  dataset = YAML.load(Dataset.get(id).yaml)
  metadata = dataset.features[feature_uri]
  
  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_feature feature_uri, metadata
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

# Get a list of all features
# @param [Header] Accept one of `application/rdf+xml, application-x-yaml, text/uri-list` (default application/rdf+xml)
# @return [application/rdf+xml, application-x-yaml, text/uri-list] Feature list 
get '/:id/features' do

  features = YAML.load(Dataset.get(params[:id]).yaml).features

  case @accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    features.each { |feature,metadata| serializer.add_feature feature, metadata }
    serializer.to_rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    features.to_yaml
  when "text/uri-list"
    response['Content-Type'] = 'text/uri-list'
    YAML.load(Dataset.get(params[:id]).yaml).features.keys.join("\n") + "\n"
  end
end

# Get a list of all compounds
# @return [text/uri-list] Feature list 
get '/:id/compounds' do
  response['Content-Type'] = 'text/uri-list'
  YAML.load(Dataset.get(params[:id]).yaml).compounds.join("\n") + "\n"
end

# Create a new dataset.
#
# Posting without parameters creates and saves an empty dataset (with assigned URI).
# Posting with parameters creates and saves a new dataset.
# Data can be submitted either
# - in the message body with the appropriate Content-type header or
# - as file uploads with Content-type:multipart/form-data and a specified file type
# @example
#   curl -X POST -F "file=@training.csv;type=text/csv" http://webservices.in-silico.ch/dataset
# @param [Header] Content-type one of `application/x-yaml, application/rdf+xml, multipart/form-data/`
# @param [BODY] - string with data in selected Content-type
# @param [optional] file, for file uploads, Content-type should be multipart/form-data, please specify the file type `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` 
# @return [text/uri-list] Task URI or Dataset URI (empty datasets)
post '/?' do 
  @dataset = Dataset.create
  response['Content-Type'] = 'text/uri-list'
  @dataset.token_id = params[:token_id] if params[:token_id]
  @dataset.token_id = request.env['HTTP_TOKEN_ID'] if !@dataset.token_id and request.env['HTTP_TOKEN_ID']

  @dataset.update(:uri => url_for("/#{@dataset.id}", :full))

  if params.size < 2 # and request.env["rack.input"].read.empty?  # mr to fix
    @dataset.update(:yaml => OpenTox::Dataset.new(@dataset.uri).to_yaml)
    @dataset.uri
  else
    task = OpenTox::Task.create("Converting and saving dataset ", @dataset.uri) do 
      @dataset.load params, request 
      @dataset.uri
    end
    halt 503,task.uri+"\n" if task.status == "Cancelled"
    halt 202,task.uri+"\n"
  end
end

# Save a dataset, will overwrite all existing data
#
# Data can be submitted either
# - in the message body with the appropriate Content-type header or
# - as file uploads with Content-type:multipart/form-data and a specified file type
# @example
#   curl -X POST -F "file=@training.csv;type=text/csv" http://webservices.in-silico.ch/dataset/1
# @param [Header] Content-type one of `application/x-yaml, application/rdf+xml, multipart/form-data/`
# @param [BODY] - string with data in selected Content-type
# @param [optional] file, for file uploads, Content-type should be multipart/form-data, please specify the file type `application/rdf+xml, application-x-yaml, text/csv, application/ms-excel` 
# @return [text/uri-list] Task ID 
post '/:id' do 
  @dataset = Dataset.get(params[:id])
  halt 404, "Dataset #{params[:id]} not found." unless @dataset
  response['Content-Type'] = 'text/uri-list'
  task = OpenTox::Task.create("Converting and saving dataset ", @dataset.uri) do 
    @dataset.load params, request 
    FileUtils.rm Dir["public/#{params[:id]}.*"]
    @dataset.uri
  end
  halt 503,task.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

# Delete a dataset
# @return [text/plain] Status message
delete '/:id' do
  begin
    dataset = Dataset.get(params[:id])
    uri = dataset.uri
    FileUtils.rm Dir["public/#{params[:id]}.*"]
    dataset.destroy!
    if params[:token_id] and !Dataset.get(params[:id]) and uri
      begin
        aa = OpenTox::Authorization.delete_policies_from_uri(uri, params[:token_id])
        LOGGER.debug "Policy deleted for Dataset URI: #{uri} with result: #{aa}"
      rescue
        LOGGER.warn "Policy delete error for Dataset URI: #{uri}"
      end
    end
    response['Content-Type'] = 'text/plain'
    "Dataset #{params[:id]} deleted."
  rescue
    halt 404, "Dataset #{params[:id]} does not exist."
  end
end

# Delete all datasets
# @return [text/plain] Status message
delete '/?' do
  FileUtils.rm Dir["public/*.rdfxml"]
  FileUtils.rm Dir["public/*.xls"]
  Dataset.auto_migrate!
  response['Content-Type'] = 'text/plain'
  "All datasets deleted."
end
