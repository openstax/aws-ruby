module OpenStax::Aws
  class Template

    class TemplateInvalid < StandardError
      attr_reader :template_path, :template_body

      def initialize(msg, template_path, template_body)
        @template_path = template_path
        @template_body = template_body

        super(msg)
      end
    end

    attr_reader :absolute_file_path, :env_name, :namespace

    def initialize(absolute_file_path:, namespace:, env_name: nil)
      @absolute_file_path = absolute_file_path
      @namespace = namespace
      @env_name = env_name

      raise "`namespace` cannot be blank" if namespace.blank?

      validate
      upload
    end

    def basename
      File.basename(absolute_file_path)
    end

    def body
      @body ||= File.read(absolute_file_path)
    end

    def valid?
      begin
        validate
      rescue TemplateInvalid
        return false
      end

      true
    end

    def s3_key
      # e.g. "may5/interactions/app.yml"
      ["cfn_templates", env_name, namespace, basename].compact.join("/")
    end

    def s3_url
      "https://s3.amazonaws.com/#{OpenStax::Aws.configuration.cfn_template_bucket_name}/#{s3_key}"
    end

  protected

    def validate
      begin
        # any region works here
        Aws::CloudFormation::Client.new(region: "us-west-2").validate_template(template_body: body)
      rescue Aws::CloudFormation::Errors::ValidationError => ee
        raise TemplateInvalid.new(basename + ": " + ee.message, absolute_file_path, body)
      end
    end

    def upload
      client = Aws::S3::Client.new(region: OpenStax::Aws.configuration.cfn_template_bucket_region)
      client.put_object({
        body: body,
        bucket: OpenStax::Aws.configuration.cfn_template_bucket_name,
        key: s3_key
      })
    end

  end
end
