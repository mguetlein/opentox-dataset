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
		compounds = {
			'[O-][N+](=O)C/C=C\C(=O)Cc1cc(C#N)ccc1' => 'true',
			'F[B-](F)(F)F.[Na+]' => 'false',
			'N#[N+]C1=CC=CC=C1.F[B-](F)(F)F' => 'false'
		}
		post '/', :name => name
		assert last_response.ok?
		uri = last_response.body.chomp
		get uri
		assert last_response.ok?
    assert last_response.body.include?("Test_dataset")

		compounds.each do |smiles,activity|

			compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
			feature_uri = OpenTox::Feature.new(:name => name, :values => {:classification => activity}).uri
			put uri, :compound_uri => compound_uri, :feature_uri => feature_uri

			assert last_response.ok?
			get uri + '/compounds'
			assert last_response.ok?
			assert last_response.body.include?(compound_uri)
			get uri + '/features'
			assert last_response.ok?
			assert last_response.body.include?(activity)
			assert last_response.body.include?(feature_uri)
			get uri + '/compound/' + compound_uri + '/features'
			assert last_response.ok?
			assert last_response.body.include?(activity)
			assert_equal feature_uri, last_response.body
		end
		get uri + '/compounds'
		#puts last_response.body
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
		get uri + '/features'
		assert last_response.ok?
		assert last_response.body.include?("Hamster%20Carcinogenicity/classification/true")
		assert last_response.body.include?("Hamster%20Carcinogenicity/classification/false")
		get uri + '/compound/' + compound_uri + '/features'
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
=end

	def test_tanimoto_similarity
		#@feature_set = OpenTox::Algorithms::Fminer.new :dataset_uri => @dataset
		name = "Similarity test dataset"
		data = {
			'[O-][N+](=O)C/C=C\C(=O)Cc1cc(C#N)ccc1' =>
			{
				'A' => 1.0,
				'B' => 0.9,
				'C' => 0.8,
				'D' => 0.7,
				'E' => 0.5
			},
			'F[B-](F)(F)F.[Na+]' => 
			{
				'F' => 0.9,
				'B' => 0.9,
				'C' => 0.8,
				'D' => 0.7,
				'E' => 0.5
			},
			'N#[N+]C1=CC=CC=C1.F[B-](F)(F)F' => 
			{
				'A' => 1.0,
				'B' => 0.9,
				'F' => 0.9,
			}
		}
		post '/', :name => name
		assert last_response.ok?
		uri = last_response.body
		get uri
		assert last_response.ok?

		data.each do |smiles,features|
			compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
			features.each do |k,v|
				feature_uri = OpenTox::Feature.new(:name => k, :values => {:p_value => v}).uri
				put uri, :compound_uri => compound_uri, :feature_uri => feature_uri
				assert last_response.ok?
			end
		end

		data.each do |smiles,features|
			compound_uri = OpenTox::Compound.new(:smiles => smiles).uri
			data.each do |s,f|
				unless s == smiles
					neighbor_uri = OpenTox::Compound.new(:smiles => s).uri
					get uri + "/tanimoto/compound/#{compound_uri}/compound/#{neighbor_uri}"
					assert last_response.ok?
					sim = last_response.body
					features_a = data[smiles].keys
					features_b = data[s].keys
					union = features_a | features_b
					intersect  = features_a & features_b
					mysim = intersect.size.to_f/union.size.to_f
					assert_equal sim, mysim.to_s
					puts "tanimoto::#{smiles}::#{s}::#{last_response.body}"
					get uri + "/weighted_tanimoto/compound/#{compound_uri}/compound/#{neighbor_uri}"
					assert last_response.ok?
					puts "weighted_tanimoto::#{smiles}::#{s}::#{last_response.body}"
				end
			end
		end

	end

=begin
	def test_unauthorized_create
		post '/', :name => "Test dataset"
		assert !last_response.ok?
	end
=end

end
