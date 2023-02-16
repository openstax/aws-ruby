lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "openstax/aws/version"

Gem::Specification.new do |spec|
  spec.name          = "openstax_aws"
  spec.version       = OpenStax::Aws::VERSION
  spec.authors       = ["JP Slavinsky"]
  spec.email         = ["jps@kindlinglabs.com"]

  spec.summary       = %q{openstax IaC}
  spec.description   = %q{openstax IaC}
  spec.homepage      = "https://github.com/openstax/aws-ruby"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}).grep_v(%r{/templates/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-autoscaling", "~> 1"
  spec.add_dependency "aws-sdk-cloudformation", "~> 1"
  spec.add_dependency "aws-sdk-cloudfront", "~> 1"
  spec.add_dependency "aws-sdk-cloudwatch", "~> 1"
  spec.add_dependency "aws-sdk-ec2", "~> 1"
  spec.add_dependency "aws-sdk-eventbridge", "~> 1"
  spec.add_dependency "aws-sdk-kafka", "~> 1"
  spec.add_dependency "aws-sdk-rds", "~> 1"
  spec.add_dependency "aws-sdk-s3", "~> 1"
  spec.add_dependency "aws-sdk-ssm", "~> 1"

  spec.add_dependency "activesupport"
  spec.add_dependency "git"
  spec.add_dependency "nokogiri"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "awesome_print"
  spec.add_development_dependency "vcr", ">= 6.1"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "dotenv"
end
