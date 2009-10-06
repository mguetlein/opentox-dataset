class Dataset

	attr_reader :uri, :members

	# key: /datasets
	# set: dataset uris
	# key: :dataset_uri/compounds
	# set: compound uris
	# key: :dataset_uri/features
	# set: feature uris
	# key: :dataset_uri/compound/:inchi
	# set: feature uris
	
	def initialize(uri)
		@uri = uri
	end

	def name
		URI.unescape File.basename(uri)
	end

	def self.create(uri)
		@@redis.set_add "datasets", uri
		Dataset.new(uri)
	end

	def self.find(uri)
		Dataset.new(uri) if @@redis.set_member? "datasets", uri
	end

	def self.find_or_create(uri)
		Dataset.find(uri) or Dataset.create(uri) 
	end

	def self.find_all
		@@redis.set_members "datasets"
	end

	def compounds
		@@redis.set_members(File.join(@uri,'compounds'))
	end

	def features
		@@redis.set_members(File.join(@uri,'features'))
	end

	def compound_features(compound_uri)
		@@redis.set_members(File.join(@uri,'compound',inchi(compound_uri)))
	end

	def add(yaml)
		YAML.load(yaml).each do |compound_uri,feature_uris|
			@@redis.set_add File.join(@uri,'compounds'), compound_uri
			feature_uris.each do |feature_uri|
				@@redis.set_add File.join(@uri,'features'), feature_uri
				@@redis.set_add File.join(@uri,'compound',inchi(compound_uri)), feature_uri
			end
		end
	end

	def delete
		@@redis.set_members(File.join(@uri,'compounds')).each do |compound_uri|
			@@redis.delete File.join(@uri,'compound',inchi(compound_uri))
		end
		@@redis.delete(File.join(@uri,'compounds'))
		@@redis.delete(File.join(@uri,'features'))
		@@redis.delete @uri 
		@@redis.set_delete "datasets", @uri
	end

	def inchi(compound_uri)
		inchi = compound_uri.sub(/^.*\/InChI/,'InChI')
	end

end
