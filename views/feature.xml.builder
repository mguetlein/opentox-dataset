xml.instruct!
xml.dataset do
	@features.each do |feature,compounds|
		xml.feature do
			xml.uri feature
			compounds.each do |c|
				xml.compound_uri c
			end
		end
	end
end
