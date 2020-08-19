require "aws-sdk-autoscaling"
require "aws-sdk-cloudformation"
require "aws-sdk-cloudfront"
require "aws-sdk-ec2"
require "aws-sdk-kafka"
require "aws-sdk-rds"
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

    def self.verify_template_bucket_access!
      begin
        ::Aws::S3::Client.new(region: configuration.cfn_template_bucket_region)
                       .head_bucket(bucket: configuration.cfn_template_bucket_name)
      rescue ::Aws::S3::Errors::Forbidden => ee
        raise "The provided AWS credentials cannot access the template bucket. Please " \
              "verify that you are using the correct credentials for the targeted AWS account."
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
      attr_accessor :stack_waiter_max_attempts
      attr_accessor :infer_stack_capabilities
      attr_accessor :infer_parameter_defaults
      attr_accessor :production_env_name
      attr_accessor :fixed_s3_template_folder
      attr_accessor :default_cycle_if_different_parameter
      attr_writer :required_stack_tags

      def initialize
        @stack_waiter_delay = 30
        @stack_waiter_max_attempts = 180
        @cfn_template_bucket_folder = "cfn_templates"
        @infer_stack_capabilities = true
        @infer_parameter_defaults = true
        @production_env_name = "production"
        @default_cycle_if_different_parameter = "CycleIfDifferent"
        @required_stack_tags = %w(Application Environment Owner)
      end

      def required_stack_tags
        # Make sure always returned as an array
        [@required_stack_tags].compact.uniq.flatten
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
        @logger ||= Logger.new(STDERR).tap do |the_logger|
          the_logger.formatter = proc do |severity, datetime, progname, msg|
            date_format = datetime.strftime("%Y-%m-%d %H:%M:%S.%3N")
            if severity == "INFO" or severity == "WARN"
                "[#{date_format}] #{severity}  | #{msg}\n"
            else
                "[#{date_format}] #{severity} | #{msg}\n"
            end
          end
        end
      end

      # Sometimes you want to make a Stack object without requirng stack tags,
      # e.g. if you're just inspecting a stack.  Wrapping such instantiations
      # with this method enables this, e.g. without_required_stack_tags do ... end
      def without_required_stack_tags
        begin
          original_required_stack_tags = required_stack_tags
          self.required_stack_tags = []
          yield
        ensure
          self.required_stack_tags = original_required_stack_tags
        end
      end
    end

  end
end

require "openstax/aws/extensions"
require "openstax/aws/tag"
require "openstax/aws/version"
require "openstax/aws/s3_text_file"
require "openstax/aws/wait_message"
require "openstax/aws/git_helper"
require "openstax/aws/template"
require "openstax/aws/distribution"
require "openstax/aws/change_set"
require "openstax/aws/stack_parameters"
require "openstax/aws/secrets_set"
require "openstax/aws/secrets_specification"
require "openstax/aws/secrets"
require "openstax/aws/secrets_factory"
require "openstax/aws/stack"
require "openstax/aws/stack_event"
require "openstax/aws/stack_status"
require "openstax/aws/stack_factory"
require "openstax/aws/deployment_base"
require "openstax/aws/ec2_instance_data"
require "openstax/aws/auto_scaling_group"
require "openstax/aws/auto_scaling_instance"
require "openstax/aws/rds_instance"
require "openstax/aws/msk_cluster"
require "openstax/aws/packer_1_2_5"
require "openstax/aws/packer_1_4_1"
require "openstax/aws/packer_factory"
require "openstax/aws/build_image_command_1"
require "openstax/aws/image"
