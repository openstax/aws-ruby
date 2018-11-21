require "aws-sdk-s3"
require 'aws-sdk-cloudformation'
require 'aws-sdk-ssm'
require "aws-sdk-ec2"
require "aws-sdk-autoscaling"

require "openstax/aws/extensions"
require "openstax/aws/version"
require "openstax/aws/git_helper"
require "openstax/aws/parameters_specification"
require "openstax/aws/parameters"
require "openstax/aws/deployment_base"
require "openstax/aws/build_image_command"

module OpenStax
  module Aws

    def self.verify_secrets_populated!
      if ENV['AWS_ACCESS_KEY_ID'].nil? || ENV['AWS_SECRET_ACCESS_KEY'].nil?
        raise "AWS key and secret are not both set!"
      end
    end

  end
end
