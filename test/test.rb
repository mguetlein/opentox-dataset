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
		name = "Test dataset"
		smiles = '[O-][N+](=O)C/C=C\C(=O)Cc1cc(C#N)ccc1'
		compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
		feature_uri = OpenTox::Feature.new(:name => name, :values => {:classification => "true"}).uri
		post '/', :name => name
		assert last_response.ok?
		uri = last_response.body.chomp
		get uri
		assert last_response.ok?
    assert last_response.body.include?("Test_dataset")
		put uri, :compound_uri => compound_uri, :feature_uri => feature_uri
		assert last_response.ok?
		get uri + '/compounds'
		assert last_response.ok?
		assert_equal compound_uri, last_response.body
		get uri + '/features'
		assert last_response.ok?
    assert last_response.body.include?("true")
		assert_equal feature_uri, last_response.body
		get uri + '/' + compound_uri + '/features'
		assert last_response.ok?
    assert last_response.body.include?("true")
		assert_equal feature_uri, last_response.body
		delete uri
		assert last_response.ok?
		get "/Test_dataset"
		assert !last_response.ok?
	end

	def test_create_dataset_from_csv
		smiles = 'CC(=O)Nc1scc(n1)c1ccc(o1)[N+](=O)[O-]'
		compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
		post '/', :name => "Hamster Carcinogenicity", :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "hamster_carcinogenicity.csv"))
		uri = last_response.body
		get uri
		assert last_response.ok?
		get uri + '/compounds'
		assert last_response.ok?
		assert last_response.body.include?(compound_uri)
		get uri + '/' + compound_uri + '/features'
		assert last_response.ok?
    assert last_response.body.include?("Hamster%20Carcinogenicity/classification/true")
		delete uri
		assert last_response.ok?
		get uri
		assert !last_response.ok?
	end

=begin
	def test_create_large_dataset_from_csv
		post '/', :name => "Salmonella Mutagenicity", :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "kazius.csv"))
		uri = last_response.body
		get uri
		assert last_response.ok?
	end

	def test_unauthorized_create
		post '/', :name => "Test dataset"
		assert !last_response.ok?
	end
=end

end
