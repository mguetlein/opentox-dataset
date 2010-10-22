require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.6.6"
require 'opentox-ruby-api-wrapper'
require 'parser'

class Dataset

  include DataMapper::Resource
  property :id, Serial
  property :uri, String, :length => 255
  property :yaml, Text, :length => 2**32-1 
  property :created_at, DateTime

end

DataMapper.auto_upgrade!


## REST API

get '/?' do
  response['Content-Type'] = 'text/uri-list'
  Dataset.all(params).collect{|d| d.uri}.join("\n") + "\n"
end

get '/:id' do

  accept = request.env['HTTP_ACCEPT']
  accept = 'application/rdf+xml' if accept == '*/*' or accept == '' or accept.nil?

  begin
    dataset = OpenTox::Dataset.from_yaml(Dataset.get(params[:id]).yaml)
    halt 404, "Dataset #{params[:id]} not found." if dataset.nil? # not sure how an empty dataset can be returned, but if this happens stale processes keep runing at 100% cpu
  rescue => e
    LOGGER.error e.message
    LOGGER.info e.backtrace
    halt 404, "Dataset #{params[:id]} not found."
  end
  
  case accept

  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    file = "public/#{params[:id]}.rdfxml"
    if File.exists? file
      response['Content-Type'] = 'application/rdf+xml'
      #redirect url_for("/#{params[:id]}",:full)+ ".rdfxml" # confuses curl (needs -L flag)
      File.read(file)
    else
      task_uri = OpenTox::Task.as_task("Converting dataset to OWL-DL (RDF/XML)", url_for(params[:id],:full)) do 
        File.open(file,"w+") { |f| f.puts dataset.rdfxml }
        url_for("/#{params[:id]}",:full)+ ".rdfxml"
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task_uri.to_s+"\n"
    end

  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    dataset.yaml
 
  when "text/csv"
    response['Content-Type'] = 'text/csv'
    dataset.csv

  when /ms-excel/
    file = "public/#{params[:id]}.xls"
    if File.exists? file
      response['Content-Type'] = 'application/ms-excel'
      File.read(file)
    else
      task_uri = OpenTox::Task.as_task("Converting dataset to Excel", url_for(params[:id],:full)) do 
        dataset.excel.write(file)
        url_for("/#{params[:id]}",:full)+ ".xls"
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task_uri.to_s+"\n"
    end

  else
    halt 404, "Content-type #{accept} not supported."
  end
end

get '/:id/metadata/?' do

  metadata = YAML.load(Dataset.get(params[:id]).yaml).metadata
  accept = request.env['HTTP_ACCEPT']
  accept = 'application/rdf+xml' if accept == '*/*' or accept == '' or accept.nil?
  
  case accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_metadata url_for(params[:id],:full), "Dataset", metadata
    serializer.rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

get %r{/(\d+)/feature/(.*)$} do |id,feature|

  feature_uri = url_for("/#{id}/feature/#{feature}",:full)
  dataset = OpenTox::Dataset.from_yaml(Dataset.get(id).yaml)
  metadata = dataset.features[feature_uri]

  accept = request.env['HTTP_ACCEPT']
  accept = 'application/rdf+xml' if accept == '*/*' or accept == '' or accept.nil?
  
  case accept
  when /rdf/ # redland sends text/rdf instead of application/rdf+xml
    response['Content-Type'] = 'application/rdf+xml'
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_feature feature_uri, metadata
    serializer.rdfxml
  when /yaml/
    response['Content-Type'] = 'application/x-yaml'
    metadata.to_yaml
  end

end

get '/:id/features/?' do
  response['Content-Type'] = 'text/uri-list'
  YAML.load(Dataset.get(params[:id]).yaml).features.keys.join("\n") + "\n"
end

get '/:id/compounds/?' do
  response['Content-Type'] = 'text/uri-list'
  YAML.load(Dataset.get(params[:id]).yaml).compounds.join("\n") + "\n"
end

post '/?' do # create an empty dataset
  response['Content-Type'] = 'text/uri-list'
  dataset = Dataset.create
  dataset.update(:uri => url_for("/#{dataset.id}", :full))
  dataset.update(:yaml => OpenTox::Dataset.new(url_for("/#{dataset.id}", :full)).to_yaml)
  "#{dataset.uri}\n"
end

post '/:id/?' do # insert data into a dataset

  begin
    dataset = Dataset.get(params[:id])
    halt 404, "Dataset #{params[:id]} not found." unless dataset
    data = request.env["rack.input"].read

    content_type = request.content_type
    content_type = "application/rdf+xml" if content_type.nil?

    case content_type

    when /yaml/
      dataset.update(:yaml => data)

    when "application/rdf+xml"
      dataset.update(:yaml => OpenTox::Dataset.from_rdfxml(data).yaml)

    when /multipart\/form-data/ # for file uploads

      case params[:file][:type]

      when /yaml/
        dataset.update(:yaml => params[:file][:tempfile].read)

      when "application/rdf+xml"
        dataset.update(:yaml => OpenTox::Dataset.from_rdfxml(params[:file][:tempfile]).yaml)

      when "text/csv"
        metadata = {DC.title => File.basename(params[:file][:filename],".csv"), OT.hasSource => File.basename(params[:file][:filename])}
        d = OpenTox::Dataset.from_csv(File.open(params[:file][:tempfile]).read)
        d.add_metadata metadata
        dataset.update(:yaml => d.yaml, :uri => d.uri)

      when /ms-excel/
        extension =  File.extname(params[:file][:filename])
        metadata = {DC.title => File.basename(params[:file][:filename],extension), OT.hasSource => File.basename(params[:file][:filename])}
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
          halt 404, "#{params[:file][:filename]} is not a valid Excel input file."
        end
        d = OpenTox::Dataset.from_spreadsheet(book)
        d.add_metadata metadata
        dataset.update(:yaml => d.yaml, :uri => d.uri)

      else
        halt 404, "MIME type \"#{params[:file][:type]}\" not supported."
      end

    else
      halt 404, "MIME type \"#{content_type}\" not supported."
    end

    FileUtils.rm Dir["public/#{params[:id]}.*"] # delete all serialization files, will be recreated at next reques
    response['Content-Type'] = 'text/uri-list'
    "#{dataset.uri}\n"

  rescue => e
    LOGGER.error e.message
    LOGGER.info e.backtrace
    halt 500, "Could not save dataset #{dataset.uri}."
  end
end

delete '/:id/?' do
  begin
    dataset = Dataset.get(params[:id])
    FileUtils.rm Dir["public/#{params[:id]}.*"]
    dataset.destroy!
    response['Content-Type'] = 'text/plain'
    "Dataset #{params[:id]} deleted."
  rescue
    halt 404, "Dataset #{params[:id]} does not exist."
  end
end

delete '/?' do
  Dataset.all {|d| FileUtils.rm Dir["public/#{d.id}.*"] }
  Dataset.auto_migrate!
  response['Content-Type'] = 'text/plain'
  "All datasets deleted."
end
