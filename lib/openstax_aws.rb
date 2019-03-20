require "aws-sdk"

require "pp"
require "openstax/aws/extensions"
require "openstax/aws/version"
require "openstax/aws/wait_message"
require "openstax/aws/git_helper"
require "openstax/aws/template"
require "openstax/aws/distribution"
require "openstax/aws/change_set_description"
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
      attr_writer :hosted_zone_name
      attr_writer :cfn_template_bucket_name
      attr_writer :log_bucket_name
      attr_writer :logger
      attr_writer :key_pair_name

      def hosted_zone_name
        raise "hosted_zone_name isn't set!" if @hosted_zone_name.blank?
        @hosted_zone_name
      end

      def cfn_template_bucket_name
        raise "template_bucket_name isn't set!" if @cfn_template_bucket_name.blank?
        @cfn_template_bucket_name
      end

      def cfn_template_bucket_region
        @cfn_template_bucket_region ||= ::Aws::S3::Client.new(region: "us-east-1") # could be any region
          .get_bucket_location(bucket: cfn_template_bucket_name)
          .location_constraint
      end

      def log_bucket_name
        raise "log_bucket_name isn't set!" if @log_bucket_name.blank?
        @log_bucket_name
      end

      def key_pair_name
        raise "key_pair_name isn't set!" if @key_pair_name.blank?
        @key_pair_name
      end

      def logger
        @logger ||= Logger.new(STDOUT)
      end
    end

  end
end
