ENV['RACK_ENV'] = 'test'
require 'application'
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
		#authorize "api", API_KEY
		post '/', :name => "Test dataset"
		assert last_response.ok?
		assert_equal "http://example.org/1", last_response.body.chomp
	end

	def test_create_dataset_and_insert_data
		#authorize "api", API_KEY
		post '/', :name => "Test dataset"
		post '/1', :compound_uri => "test_compound_uri", :feature_uri => "test_feature_uri"
		get '/1'
		assert last_response.ok?
    assert last_response.body.include?('Test dataset')
    assert last_response.body.include?('test_compound_uri')
    assert last_response.body.include?('test_feature_uri')
	end

=begin
	def test_unauthorized_create
		post '/', :name => "Test dataset"
		assert !last_response.ok?
	end
=end

end
