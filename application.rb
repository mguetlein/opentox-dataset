require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.6.0"
require 'opentox-ruby-api-wrapper'

class Dataset
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	property :file, String, :length => 255
	property :yaml, Text, :length => 2**32-1 
	property :owl, Text, :length => 2**32-1 
	property :created_at, DateTime

	def to_owl
		data = YAML.load(yaml)
		owl = OpenTox::Owl.create 'Dataset', uri
		owl.set "title", data.title
    owl.set "creator", data.creator
    if data.compounds
      data.compounds.each do |compound|
        owl.add_data_entries compound,data.data[compound]  
       end
    end
    owl.rdf
	end

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
	# workaround for browser links
	case params[:id]
	when /.yaml$/
		params[:id].sub!(/.yaml$/,'')
		accept =  'application/x-yaml'
	when /.rdf$/
		params[:id].sub!(/.rdf$/,'')
		accept =  'application/rdf+xml'
	when /.xls$/
		params[:id].sub!(/.xls$/,'')
		accept =  'application/vnd.ms-excel'	
	end
	begin
		dataset = Dataset.get(params[:id])
    halt 404, "Dataset #{params[:id]} not found." unless dataset
	rescue => e
		raise e.message + e.backtrace
		halt 404, "Dataset #{params[:id]} not found."
	end
	halt 404, "Dataset #{params[:id]} not found." if dataset.nil? # not sure how an empty cataset can be returned, but if this happens stale processes keep runing at 100% cpo
	case accept
	when /rdf/ # redland sends text/rdf instead of application/rdf+xml
		response['Content-Type'] = 'application/rdf+xml'
		unless dataset.owl # lazy owl creation
			dataset.owl = dataset.to_owl
			dataset.save
		end
		dataset.owl
	when /yaml/
		response['Content-Type'] = 'application/x-yaml'
		dataset.yaml
  when /ms-excel/
    require 'spreadsheet'
    response['Content-Type'] = 'application/vnd.ms-excel'
    Spreadsheet.client_encoding = 'UTF-8'
    book = Spreadsheet::Workbook.new
    tmp = Tempfile.new('opentox-feature-xls')
    sheet = book.create_worksheet  :name => 'Training Data'
    sheet.column(0).width = 100
    i = 0
    YAML.load(dataset.yaml).data.each do |line|
      begin
        smilestring = RestClient.get(line[0], :accept => 'chemical/x-daylight-smiles').to_s
				if line[1]
					val = line[1][0].first[1]
					LOGGER.debug val
					#line[1][0] ? val = line[1][0].first[1] #? "1" : "0" : val = "" 
					sheet.update_row(i, smilestring , val)
				end
        i+=1 
      rescue
      end
    end
    begin    
      book.write tmp.path
      return tmp
    rescue
      
    end
    tmp.close!
  else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
end

get '/:id/features/:feature_id/?' do
	OpenTox::Dataset.find(url_for("/#{params[:id]}", :full)).feature(params[:feature_id])
end

get '/:id/features/?' do
	YAML.load(Dataset.get(params[:id]).yaml).features.join("\n") + "\n"
end

get '/:id/compounds/?' do
	YAML.load(Dataset.get(params[:id]).yaml).compounds.join("\n") + "\n"
end

post '/?' do

		dataset = Dataset.new
		dataset.save
		dataset.uri = url_for("/#{dataset.id}", :full)
		content_type = request.content_type
		content_type = "application/rdf+xml" if content_type.nil?
		case request.content_type
		when /yaml/
			dataset.yaml =	request.env["rack.input"].read
		when /csv/
			dataset.yaml =	csv2yaml request.env["rack.input"].read
		when "application/rdf+xml"
			dataset.yaml =	owl2yaml request.env["rack.input"].read
		else
			halt 404, "MIME type \"#{request.content_type}\" not supported."
		end
		begin
			#dataset.owl = d.rdf
      #dataset.uri = uri 
			raise "saving failed: "+dataset.errors.inspect unless dataset.save
		rescue => e
			LOGGER.error e.message
			LOGGER.info e.backtrace
			halt 500, "Could not save dataset #{dataset.uri}."
		end
		LOGGER.debug "#{dataset.uri} saved."
	response['Content-Type'] = 'text/uri-list'
	dataset.uri + "\n"
end

delete '/:id/?' do
	begin
		dataset = Dataset.get(params[:id])
		dataset.destroy!
		response['Content-Type'] = 'text/plain'
		"Dataset #{params[:id]} deleted."
	rescue
		halt 404, "Dataset #{params[:id]} does not exist."
	end
end

delete '/?' do
  
=begin
	Dataset.all.each do |d|
		begin
			File.delete d.file 
		rescue
			LOGGER.error "Cannot delete dataset file '#{d.file}'"
		end
	 	#d.destroy!
	end
=end
  Dataset.auto_migrate!
	response['Content-Type'] = 'text/plain'
	"All datasets deleted."
end
