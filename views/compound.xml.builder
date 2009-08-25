xml.instruct!
xml.dataset do
	@compounds.each do |compound,features|
		xml.compound do
			xml.uri compound
			features.each do |f|
				xml.feature_uri f
			end
		end
	end
end
