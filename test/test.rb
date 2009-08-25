require 'application'
require 'test/unit'
require 'rack/test'

set :environment, :test
@@redis.flush_db

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
		post '/', :name => "Test dataset"
		assert last_response.ok?
		uri = last_response.body.chomp
		assert_equal "http://example.org/Test_dataset", uri
		get uri
		assert last_response.ok?
		delete "/Test_dataset"
		assert last_response.ok?
		get "/Test_dataset"
		assert !last_response.ok?
	end

	def test_create_dataset_and_insert_data
		usmiles = OpenTox::Compound.new(:smiles => '[O-][N+](=O)C/C=C\C(=O)Cc1cc(C#N)ccc1').uid
		puts usmiles
		name = "Test dataset"
		post '/', :name => name
		assert last_response.ok?
		uri = last_response.body.chomp
		get uri
		assert last_response.ok?
    assert last_response.body.include?("Test_dataset")
		put uri, :compound => usmiles, :feature => "true"
		assert last_response.ok?
		get uri + '/compounds'
		assert last_response.ok?
    assert last_response.body.include?(usmiles)
		get uri + '/features'
		assert last_response.ok?
    assert last_response.body.include?("true")
		get uri + '/' + usmiles + '/features'
		puts last_response.body
		assert last_response.ok?
    assert last_response.body.include?("true")
		delete uri
		assert last_response.ok?
		get "/Test_dataset"
		assert !last_response.ok?
	end

	def test_create_dataset_from_csv
		post '/', :name => "Hamster Carcinogenicity", :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "hamster_carcinogenicity.csv"))
		uri = last_response.body
		get uri
		assert last_response.ok?
		get uri + '/compounds'
		assert last_response.ok?
	end

	def test_create_large_dataset_from_csv
		post '/', :name => "Salmonella Mutagenicity", :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "kazius.csv"))
		uri = last_response.body
		get uri
		assert last_response.ok?
	end

=begin
	def test_unauthorized_create
		post '/', :name => "Test dataset"
		assert !last_response.ok?
	end
=end

end
