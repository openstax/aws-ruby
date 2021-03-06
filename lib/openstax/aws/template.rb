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

    attr_reader :absolute_file_path

    def self.from_absolute_file_path(absolute_file_path)
      new(absolute_file_path: absolute_file_path)
    end

    def self.from_body(body)
      new(body: body)
    end

    def basename
      File.basename(absolute_file_path)
    end

    def extname
      File.extname(absolute_file_path)
    end

    def erb?
      extname == '.erb'
    end

    def body
      return @body unless @body.nil?

      @body = File.read(absolute_file_path)
      @body = ERB.new(@body).tap { |erb| erb.filename = absolute_file_path }.result if erb?
      @body
    end

    def hash
      json_hash || yml_hash || raise("Cannot read template #{absolute_file_path}")
    end

    def valid?
      begin
        validate
      rescue TemplateInvalid
        return false
      end

      true
    end

    def parameter_names
      hash["Parameters"].try(:keys) || []
    end

    def required_capabilities
      has_an_iam_resource = hash["Resources"].any? do |resource_id, resource_body|
        resource_body["Type"].starts_with?("AWS::IAM::")
      end

      # A bit of a cop out to claim named_iam since we haven't checked
      # to see if any of the IAM resources have custom names, but it will
      # work
      has_an_iam_resource ? [:named_iam] : []
    end

    def s3_key
      [
        OpenStax::Aws.configuration.cfn_template_bucket_folder,
        s3_folder,
        basename
      ].compact.join("/")
    end

    def s3_folder
      @unique_s3_folder ||=
        OpenStax::Aws.configuration.fixed_s3_template_folder ||
        Time.now.utc.strftime("%Y%m%d_%H%M%S_#{SecureRandom.hex(4)}")
    end

    def s3_url
      upload_once
      "https://s3.amazonaws.com/#{OpenStax::Aws.configuration.cfn_template_bucket_name}/#{s3_key}"
    end

    def upload_once
      return if @uploaded

      validate
      upload

      @uploaded = true
    end

    def is_sam?
      body.match(/Transform: .?AWS::Serverless/).present?
    end

  protected

    def initialize(absolute_file_path: nil, body: nil)
      raise "One of `absolute_file_path` or `body` must be set" if absolute_file_path.blank? && body.nil?
      @absolute_file_path = absolute_file_path
      @body = body.try(:dup)
    end

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

    def json_hash
      JSON.parse(body) rescue nil
    end

    def yml_hash
      YAML.load(body) rescue nil
    end

  end
end
