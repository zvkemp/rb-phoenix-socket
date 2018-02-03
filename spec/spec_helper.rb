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

class DockerHostDetector
  def initialize(system_command)
    @system_command = system_command
  end

  def to_s
    @to_s ||= exec&.strip
  end

  private

  def exec
    `#@system_command`.tap do
      unless $?.success?
        puts "`#@system_command` not available."
        return nil
      end
    end
  end
end

ENV['PHOENIX_HOST'] ||= [
  DockerHostDetector.new('docker-machine ip'),
  DockerHostDetector.new('boot2docker ip'),
  '0.0.0.0'
].lazy.map(&:to_s).detect(&:itself)
