set :default_content, :yaml

## REST API
get '/feature/*/?' do
	@feature = OpenTox::Feature.new(request.url)
	respond_to do |format|
		format.yaml { @feature.to_yaml }
		format.xml {  builder :feature }
	end
end

post '/feature/?' do
	OpenTox::Feature.new(:name => params[:name], :values => params[:values]).uri
end
