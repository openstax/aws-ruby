require "bundler/setup"
require 'dotenv/load'
require "byebug"

require_relative "../lib/openstax_aws"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each, :vcr) do
    # Values don't matter in playback, but the code objects if they are missing
    ENV['AWS_ACCESS_KEY_ID'] ||= 'foo'
    ENV['AWS_SECRET_ACCESS_KEY'] ||= 'bar'

    switch_to_temporary_aws_credentials
  end
end

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

OpenStax::Aws.configure do |config|
  config.key_pair_name = "dummy-kp"
end
