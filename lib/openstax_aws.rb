require "aws-sdk-autoscaling"
require "aws-sdk-cloudformation"
require "aws-sdk-cloudfront"
require "aws-sdk-ec2"
require "aws-sdk-s3"
require "aws-sdk-ssm"

require 'active_support'
require 'active_support/core_ext'

require "pp"

module OpenStax
  module Aws

    def self.verify_secrets_populated!
      if ENV['AWS_ACCESS_KEY_ID'].nil? || ENV['AWS_SECRET_ACCESS_KEY'].nil?
        raise "AWS key and secret are not both set!"
      end
    end

    def self.configure
      yield configuration
    end

    def self.configuration
      @configuration ||= Configuration.new
    end

    def self.logger
      configuration.logger
    end

    class Configuration
      attr_writer :cfn_template_bucket_name
      attr_writer :cfn_template_bucket_region
      attr_accessor :cfn_template_bucket_folder
      attr_writer :logger
      attr_accessor :stack_waiter_delay
      attr_accessor :infer_stack_capabilities
      attr_accessor :infer_parameter_defaults
      attr_accessor :production_env_name
      attr_accessor :fixed_s3_template_folder

      def initialize
        @stack_waiter_delay = 30
        @cfn_template_bucket_folder = "cfn_templates"
        @infer_stack_capabilities = true
        @infer_parameter_defaults = true
        @production_env_name = "production"
      end

      def cfn_template_bucket_name
        raise "cfn_template_bucket_name isn't set!" if @cfn_template_bucket_name.blank?
        @cfn_template_bucket_name
      end

      def cfn_template_bucket_region
        raise "cfn_template_bucket_region isn't set!" if @cfn_template_bucket_region.blank?
        @cfn_template_bucket_region

        # We used to find the region automagically with the following, but this played some havoc
        # with recorded test interactions (as it only ran in some tests since memoized).  Just
        # require manual setting now.
        #
        # @cfn_template_bucket_region ||= ::Aws::S3::Client.new(region: "us-east-1") # could be any region
        #   .get_bucket_location(bucket: cfn_template_bucket_name)
        #   .location_constraint
      end

      def logger
        @logger ||= Logger.new(STDOUT)
      end
    end

  end
end

require "openstax/aws/extensions"
require "openstax/aws/version"
require "openstax/aws/wait_message"
require "openstax/aws/git_helper"
require "openstax/aws/template"
require "openstax/aws/distribution"
require "openstax/aws/change_set"
require "openstax/aws/secrets_specification"
require "openstax/aws/secrets"
require "openstax/aws/stack"
require "openstax/aws/stack_factory"
require "openstax/aws/deployment_base"
require "openstax/aws/build_image_command"
require "openstax/aws/ec2_instance_data"
require "openstax/aws/auto_scaling_instance"
