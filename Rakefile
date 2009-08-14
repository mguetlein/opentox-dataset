require 'rubygems'
require 'rake'

desc "Install required gems"
task :install do
	puts `sudo gem install sinatra emk-sinatra-url-for builder datamapper json_pure do_sqlite3`
end

desc "Run tests"
task :test do
	load 'test.rb'
end

