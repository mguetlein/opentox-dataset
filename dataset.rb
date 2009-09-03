class Dataset

	include OpenTox::Utils
	attr_reader :uri, :name, :members

	def initialize(uri)
		@uri = uri
		begin
			@name = URI.split(uri)[5]
		rescue
			puts "Bad URI #{uri}"
		end
		@members = @@redis.set_members(uri)
	end

	def self.create(uri)
		@@redis.set_add "datasets", uri
		Dataset.new(uri)
	end

	def self.find(uri)
		if @@redis.set_member? "datasets", uri
			Dataset.new(uri)
		else
			nil
		end
	end

	def self.find_or_create(uri)
		dataset = Dataset.create(uri) unless dataset = Dataset.find(uri)
		dataset
	end

	def self.find_all_keys
		@@redis.keys "*"
	end

	def self.find_all
		@@redis.set_members "datasets"
	end

	def add(member_uri)
		@@redis.set_add @uri , member_uri
		@members << member_uri
	end

	def union(set_uri)
		@@redis.set_union(@uri,set_uri)
	end

	def intersection(set_uri)
		@@redis.set_intersect(@uri,set_uri)
	end

	def tanimoto(set_uri)
		union_size = @@redis.set_union(@uri,set_uri).size
		intersect_size = @@redis.set_intersect(@uri,set_uri).size
		"#{intersect_size.to_f/union_size.to_f}"
	end

	def weighted_tanimoto(set_uri)
		union = @@redis.set_union(@uri,set_uri)
		intersect = @@redis.set_intersect(@uri,set_uri)

		p_sum_union = 0.0
		p_sum_intersect = 0.0

		union.each{ |f| p_sum_union += OpenTox::Utils::gauss(Feature.value(f,'p_value').to_f) }
		intersect.each{ |f| p_sum_intersect += OpenTox::Utils::gauss(Feature.value(f,'p_value').to_f) }
		"#{p_sum_intersect/p_sum_union}"
	end

	def delete
		@@redis.delete @uri 
		@@redis.set_delete "datasets", @uri
	end

end

=begin
class Dataset

	include OpenTox::Utils
	attr_reader :uri, :name

	def initialize(uri)
		@name = File.basename(uri)
		@uri = uri
		@members = []
	end

	def self.create(uri)
		dataset = Dataset.new(uri)
		dataset.save
		dataset
	end

	def self.find(uri)
		if @@redis.set_member? "datasets", uri
			Dataset.new(uri)
		else
			nil
		end
	end

	def self.exists?(uri)
		@@redis.set_member? "datasets", uri
	end

	def self.find_all
		@@redis.set_members("datasets")
	end

	def save
		@@redis.set_add "datasets", @uri
	end

	def destroy
		@@redis.set_members(@uri + '::compounds').each do |compound_uri|
			@@redis.delete @uri + '::' + compound_uri
		end
		@@redis.delete @uri + '::compounds'
		@@redis.set_members(@uri + '::features').each do |feature_uri|
			@@redis.delete @uri + '::' + feature_uri
		end
		@@redis.delete @uri + '::features'
		@@redis.set_delete "datasets", @uri
	end

	def add(compound_uri,feature_uri)
		@@redis.set_add @uri + '::compounds', compound_uri
		@@redis.set_add @uri + '::features', feature_uri
		@@redis.set_add @uri + '::' + compound_uri + '::features', feature_uri
		@@redis.set_add @uri + '::' + feature_uri + '::compounds', compound_uri
	end

	def compound_uris
		@@redis.set_members(@uri + "::compounds")
	end

	def feature_uris
		@@redis.set_members(@uri + "::features")
	end

	def feature_uris_for_compound(compound_uri)
		@@redis.set_members(@uri + '::' + compound_uri + '::features')
	end
	 
	def compound_uris_for_feature(feature_uri)
		@@redis.set_members(@uri + '::' + feature_uri + '::compounds')
	end

	def self.tanimoto(features)
		raise "Exactly 2 compounds are needed for similarity calculations" unless features.size == 2
		compound_keys = features.collect{ |f| f[:dataset_uri] + '::' + f[:compound_uri] + "::features" }
		union_size = @@redis.set_union(compound_keys[0], compound_keys[1]).size
		intersect_size = @@redis.set_intersect(compound_keys[0], compound_keys[1]).size
		intersect_size.to_f/union_size.to_f
	end

	def self.weighted_tanimoto(features)
		raise "Exactly 2 compounds are needed for similarity calculations" unless features.size == 2
		compound_keys = features.collect{ |f| f[:dataset_uri] + '::' + f[:compound_uri] + "::features" }
		union = @@redis.set_union(compound_keys[0], compound_keys[1])
		intersect = @@redis.set_intersect(compound_keys[0], compound_keys[1])

		p_sum_union = 0.0
		p_sum_intersect = 0.0

		union.each{ |f| p_sum_union += OpenTox::Utils::gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		intersect.each{ |f| p_sum_intersect += OpenTox::Utils::gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		"#{p_sum_intersect/p_sum_union}"
	end

end

class Dataset

	attr_accessor :uri, :set_uris

	def initialize(uri, set_uris)
		@uri = uri
		@set_uris = set_uris
	end

	def self.create(uri, set_uris)
		collection = DatasetCollection.new(uri, set_uris)
		collection.save
		collection
	end

	def self.find(uri)
		if @@redis.set_member? "collections", uri
			set_uris = @@redis.set_members uri
			DatasetCollection.new(uri, set_uris)
		else
			nil
		end
	end

	def self.exists?(uri)
		@@redis.set_member? "collections", uri
	end

	def self.find_all
		@@redis.set_members("collections").collect{ |uri| self.find(uri) }
	end

	def save
		@@redis.set_add "collections", @uri
		@set_uris.each do |uri|
			@@redis.set_add @uri + '::sets', uri
		end
	end

	def destroy
		@set_uris.each do |uri|
			Dataset.new(uri).destroy
		end
		@@redis.delete @uri + '::sets'
		@@redis.set_delete "collections", @uri
	end

	def add(set_uri)
		@set_uris << set_uri
		@@redis.set_add @uri, set_uri
	end

end
=end
