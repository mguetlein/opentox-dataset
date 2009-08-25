xml.instruct!
xml.dataset do
	xml.uri url_for("/", :full) + @dataset.id.to_s
	xml.name @dataset.name
	xml.finished @dataset.finished
end

