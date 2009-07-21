ENV['RACK_ENV'] = 'test'
require 'datasets'
require 'test/unit'
require 'rack/test'


class DatasetsTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

	def test_index
		get '/'
		assert last_response.ok?
	end

	def test_create_dataset
		authorize "api", API_KEY
		post '/', :dataset_name => "Test dataset"
		assert last_response.ok?
		assert_equal "http://example.org/1", last_response.body.chomp
	end

	def test_create_dataset_and_insert_data
		authorize "api", API_KEY
		post '/', :dataset_name => "Test dataset"
		puts last_response.body
		put '/1', :feature_name => "New feature", :feature_value => "inactive", :compound_name => 'Benzene'
		puts last_response.body
		put '/1', :feature_name => "New feature", :feature_value => "active", :compound_name => 'Dioxin'
		get '/1'
		puts last_response.body.chomp
		assert last_response.ok?
	end

	def test_unauthorized_create
		post '/', :dataset_name => "Test dataset", :feature_name => "Test feature", :file => File.new('tests/example.tab')
		assert !last_response.ok?
	end

	def test_post_to_existing_dataset
	end

end
