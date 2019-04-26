module OpenStax::Aws
  class DeploymentBase

    attr_reader :env_name, :region, :name, :dry_run

    RESERVED_ENV_NAMES = [
      "external", # used to namespace external secrets in the parameter store
    ]

    def initialize(env_name: nil, region:, name:, dry_run:)
      if RESERVED_ENV_NAMES.include?(env_name)
        raise "#{env_name} is a reserved word and cannot be used as an environment name"
      end

      # Allow a blank env_name but normalize it to `nil`
      @env_name = env_name.blank? ? nil : env_name
      @region = region
      @name = name
      @dry_run = dry_run
    end

    def name!
      raise "`name` is blank" if name.blank?
      name
    end

    def env_name!
      raise "`env_name` is blank" if env_name.blank?
      env_name
    end

    def new_stack(name_suffix:, template_path:, capabilities: nil)
      raise "Must set a template directory first" if @template_directory.blank?

      absolute_template_path = File.join(@template_directory, template_path)

      OpenStax::Aws::Stack.new(
        name: "#{env_name}-#{name_suffix}",
        env_name: env_name,
        is_production: is_production?,
        template_namespace: @name,
        absolute_template_path: absolute_template_path,
        capabilities: capabilities,
        dry_run: dry_run
      )
    end

    def set_template_directory(*directory_parts)
      @template_directory = File.join(directory_parts)
    end

    protected

    def is_production?
      env_name == "production"
    end

    def subdomain_with_trailing_dot(site_name:)
      parts = []
      parts.push(site_name) if !site_name.blank?
      parts.push(env_name!) unless is_production?

      subdomain = parts.join("-")
      subdomain.blank? ? "" : subdomain + "."
    end

    def build_domain(site_name:)
      "#{subdomain_with_trailing_dot(site_name: site_name)}#{hosted_zone_name}"
    end

    def hosted_zone_name
      OpenStax::Aws.configuration.hosted_zone_name
    end

    def log_bucket_name
      OpenStax::Aws.configuration.log_bucket_name
    end

    def logger
      OpenStax::Aws.configuration.logger
    end

    def key_pair_name
      OpenStax::Aws.configuration.key_pair_name
    end


    def client
      @client ||= ::Aws::CloudFormation::Client.new(region: region)
    end

    def auto_scaling_client
      @auto_scaling_client ||= ::Aws::AutoScaling::Client.new(region: region)
    end

    def set_desired_capacity(asg_name:, desired_capacity:)
      auto_scaling_client.set_desired_capacity(auto_scaling_group_name: asg_name, desired_capacity: desired_capacity)
    end

    def auto_scaling_group(name:)
      ::Aws::AutoScaling::AutoScalingGroup.new(name: name, client: auto_scaling_client)
    end

    def cloudfront_client
      @cloudfront_client ||= ::Aws::CloudFront::Client.new(region: region)
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: region)
    end

    def s3_key_exists?(bucket:, key:)
      begin
        s3_client.get_object(bucket: bucket, key: key)
        true
      rescue Aws::S3::Errors::NoSuchKey
        false
      end
    end

    def wait_for_tag_change(resource:, key:, polling_seconds: 10, timeout_seconds: nil)
      keep_polling = true
      started_at = Time.now
      original_value = resource_tag_value(resource: resource, key: key)

      while keep_polling
        sleep(polling_seconds)

        keep_polling = false if resource_tag_value(resource: resource, key: key) != original_value
        keep_polling = false if !timeout_seconds.nil? && Time.now - timeout_seconds > started_at
      end
    end

    def resource_tag_value(resource:, key:)
      begin
        resource.tag(key).value
      rescue NoMethodError => ee
        nil
      end
    end

    def parameters(id: 'default')
      id = id.to_s
      @parameters ||= {}
      @parameters[id] ||= OpenStax::Aws::Parameters.new(
        region: region,
        env_name: env_name!,
        parameter_namespace: parameter_namespace(id: id)
      )
    end

    def get_image_tag(image_id:, key:)
      tag = image(image_id).tags.find{|tag| tag.key == key}
      raise "No tag with key #{key} on AMI #{image_id}" if tag.nil?
      tag.value
    end

    def image(image_id)
      Aws::EC2::Image.new(image_id, region: region)
    end

    # Returns the SHA on an AMI
    def image_sha(image_id)
      get_image_tag(image_id: image_id, key: "sha")
    end

    protected

    def parameter_namespace(id: 'default')
      raise "Override this method in your deployment class and provide a namespace " \
            "for data in the AWS Parameter Store.  The parameter key will be this namespace " \
            "prefixed by the environment name and suffixed with the parameter name."
    end

  end
end
