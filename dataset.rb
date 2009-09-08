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

	def member?(uri)
		@@redis.set_member? @uri, uri
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

		union.each{ |f| p_sum_union += OpenTox::Utils::gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		intersect.each{ |f| p_sum_intersect += OpenTox::Utils::gauss(OpenTox::Feature.new(:uri => f).value('p_value').to_f) }
		"#{p_sum_intersect/p_sum_union}"
	end

	def delete
		@@redis.delete @uri 
		@@redis.set_delete "datasets", @uri
	end

end

