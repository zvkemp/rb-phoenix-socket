require "bundler/setup"
require "phoenix/socket"
require 'pry-byebug'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

Thread.report_on_exception = true
Thread.abort_on_exception = true

ENV['PHOENIX_HOST'] ||= begin
  `docker-machine ip`.strip
rescue Errno::ENOENT
  'localhost'
end
