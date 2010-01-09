require 'rubygems'
require 'sinatra'
require 'application.rb'
require 'rack'
require 'rack/contrib'

FileUtils.mkdir_p 'log' unless File.exists?('log')
FileUtils.mkdir_p 'datasets' unless File.exists?('datasets')
log = File.new("log/#{ENV["RACK_ENV"]}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)
 
if ENV['RACK_ENV'] == 'production'
	use Rack::MailExceptions do |mail|
		mail.to 'helma@in-silico.ch'
		mail.subject '[ERROR] %s'
	end 

elsif ENV['RACK_ENV'] == 'development'
  use Rack::Reloader 
  use Rack::ShowExceptions
end

run Sinatra::Application

