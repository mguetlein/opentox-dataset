mime :uid, "text/plain"
mime :smiles, "chemical/x-daylight-smiles"
mime :inchi, "chemical/x-inchi"
mime :sdf, "chemical/x-mdl-sdfile"
mime :image, "image/gif"
mime :names, "text/plain"

set :default_content, :smiles

get '/compound/*/match/*' do
	"#{OpenTox::Compound.new(:inchi => params[:splat][0]).match(params[:splat][1])}"
end

get %r{/compound/(.+)} do |inchi| # catches all remaining get requests
	inchi.gsub!(/ /,'+') # fix CGI? escaping of + signs
	respond_to do |format|
		format.smiles { inchi2smiles inchi }
		format.names  { RestClient.get "#{CACTUS_URI}#{inchi}/names" }
		format.inchi  { inchi }
		format.sdf    { RestClient.get "#{CACTUS_URI}#{inchi}/sdf" }
		format.image  { "#{CACTUS_URI}#{inchi}/image" }
	end
end

post '/compound/?' do 
	if params[:smiles]
		OpenTox::Compound.new(:smiles => params[:smiles]).uri
	elsif params[:inchi]
		OpenTox::Compound.new(:inchi => params[:inchi]).uri
	elsif params[:name]
		OpenTox::Compound.new(:name => params[:name]).uri
	end
end
