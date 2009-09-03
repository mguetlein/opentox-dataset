require 'application'
require 'test/unit'
require 'rack/test'
require 'ruby-prof'

set :environment, :test
@@redis.flush_db

class DatasetsTest < Test::Unit::TestCase
  include Rack::Test::Methods
	#include RubyProf::Test

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
		uri = last_response.body
		assert_equal "http://example.org/Test%20dataset", uri
		get uri
		assert last_response.ok?
		delete uri
		assert last_response.ok?
		get uri
		assert !last_response.ok?
	end

	def test_create_dataset_from_csv
		smiles = 'CC(=O)Nc1scc(n1)c1ccc(o1)[N+](=O)[O-]'
		compound = Compound.new(:smiles => smiles)
		post '/', :name => "Hamster Carcinogenicity"
		uri = last_response.body
		post uri + '/activities', :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "hamster_carcinogenicity.csv"))
		get uri
		assert last_response.ok?
		get uri + '/compounds'
		assert last_response.ok?
		assert last_response.body.include?(compound.inchi)
		#get uri + '/activities'
		#assert last_response.ok?
		#assert last_response.body.include?("Hamster%20Carcinogenicity/classification/true")
		#assert last_response.body.include?("Hamster%20Carcinogenicity/classification/false")
		get File.join(uri ,compound.inchi)
		assert last_response.ok?
    assert last_response.body.include?("Hamster%20Carcinogenicity/classification/true")
		delete uri
		assert last_response.ok?
		get uri
		assert !last_response.ok?
	end

	def test_create_large_dataset_from_csv
		post '/', :name => "Salmonella Mutagenicity"
		uri = last_response.body
		post uri + '/activities', :file => Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), "kazius.csv"))
		uri = last_response.body
		get uri
		assert last_response.ok?
	end

	def test_tanimoto_similarity
		#@feature_set = OpenTox::Algorithms::Fminer.new :dataset_uri => @dataset
		name = "Similarity test dataset"
		data = {
			'c1ccccc1' =>
			#'[O-][N+](=O)C/C=C\C(=O)Cc1cc(C#N)ccc1' =>
			{
				'A' => 1.0,
				'B' => 0.9,
				'C' => 0.8,
				'D' => 0.7,
				'E' => 0.5
			},
				'CCCNN' =>
			#'F[B-](F)(F)F.[Na+]' => 
			{
				'F' => 0.9,
				'B' => 0.9,
				'C' => 0.8,
				'D' => 0.7,
				'E' => 0.5
			},
				'C1CO1' =>
			#'N#[N+]C1=CC=CC=C1.F[B-](F)(F)F' => 
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
		name = URI.encode(name)
		feature_data = {}

		data.each do |smiles,features|
			compound = Compound.new(:smiles => smiles).inchi
			feature_data[compound] = []
			features.each do |k,v|
				feature= Feature.new(:name => k, :values => {:p_value => v}).path
				feature_data[compound] << feature
			end
		end

		post uri + '/features', :features => feature_data.to_yaml
		assert last_response.ok?

		data.each do |smiles,features|
			compound= Compound.new(:smiles => smiles).inchi
			data.each do |s,f|
				unless s == smiles
					neighbor= Compound.new(:smiles => s).inchi
					get "/#{name}/#{compound}/"
					assert last_response.ok?
					get "/#{name}/#{compound}/tanimoto/#{name}/#{neighbor}"
					assert last_response.ok?
					sim = last_response.body
					features_a = data[smiles].keys
					features_b = data[s].keys
					union = features_a | features_b
					intersect  = features_a & features_b
					mysim = intersect.size.to_f/union.size.to_f
					assert_equal sim, mysim.to_s
					puts "tanimoto::#{smiles}::#{s}::#{last_response.body}"
					get "/#{name}/#{compound}/weighted_tanimoto/#{name}/#{neighbor}"
					assert last_response.ok?
					puts "weighted_tanimoto::#{smiles}::#{s}::#{last_response.body}"
				end
			end
		end

	end

end
