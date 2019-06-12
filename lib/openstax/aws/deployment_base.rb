module OpenStax::Aws
  class DeploymentBase

    attr_reader :env_name, :region, :name, :dry_run

    RESERVED_ENV_NAMES = [
      "external", # used to namespace external secrets in the parameter store
    ]

    def initialize(env_name: nil, region:, name:, dry_run: true)
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

    class << self

      def template_directory(*directory_parts)
        if method_defined?("template_directory")
          raise "Can only set template_directory once per class definition"
        end

        define_method "template_directory" do
          File.join(*directory_parts)
        end
      end

      def stack(id, &block)
        if id.blank?
          raise "The first argument to `stack` must be a non-blank ID"
        end

        if !id.to_s.match(/^[a-zA-Z][a-zA-Z0-9_]*$/)
          raise "The first argument to `stack` must consist only of letters, numbers, and underscores, " \
                "and must start with a letter."
        end

        define_method("#{id}_stack") do
          instance_variable_get("@#{id}_stack") || begin
            stack_factory = StackFactory.new(id: id, deployment: self)
            stack_factory.instance_eval(&block) if block_given?

            # Fill in missing attributes using deployment variables and conventions

            if stack_factory.name.blank?
              stack_factory.name([env_name,name,id].compact.join("-").gsub("_","-"))
            end

            if stack_factory.region.blank?
              stack_factory.region(region)
            end

            if stack_factory.dry_run.nil?
              stack_factory.dry_run(dry_run)
            end

            if stack_factory.enable_termination_protection.nil?
              stack_factory.enable_termination_protection(is_production?)
            end

            if stack_factory.absolute_template_path.blank?
              stack_factory.autoset_absolute_template_path(respond_to?(:template_directory) ? template_directory : "")
            end

            # Populate parameter defaults that match convention names

            if OpenStax::Aws.configuration.infer_parameter_defaults
              template = OpenStax::Aws::Template.from_absolute_file_path(stack_factory.absolute_template_path)
              template.parameter_names.each do |parameter_name|
                value = parameter_default(parameter_name) ||
                        built_in_parameter_default(parameter_name)

                if !value.nil?
                  stack_factory.parameter_defaults[parameter_name.underscore.to_sym] ||= value
                end
              end
            end

            stack_factory.build.tap do |stack|
              instance_variable_set("@#{id}_stack", stack)
            end
          end
        end
      end

      def secrets_substitutions(&block)
        define_method("shared_secrets_substitutions_block") do
          block
        end
      end

    end

    def built_in_parameter_default(parameter_name)
      case parameter_name
      when "EnvName"
        env_name
      when /(.+)StackName$/
        send("#{$1}Stack".underscore).name rescue nil
      end
    end

    def shared_secrets_substitutions_block
      nil # can be overridden by the DSL
    end

    protected

    def parameter_default(parameter_name)
      nil
    end

    def is_production?
      env_name == OpenStax::Aws.configuration.production_env_name
    end

    def subdomain_with_trailing_dot(site_name:)
      parts = []
      parts.push(site_name) if !site_name.blank?
      parts.push(env_name!) unless is_production?

      subdomain = parts.join("-")
      subdomain.blank? ? "" : subdomain + "."
    end

    delegate :logger, to: :configuration

    def configuration
      OpenStax::Aws.configuration
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

    def secrets(id: 'default')
      id = id.to_s
      @secrets ||= {}
      @secrets[id] ||= OpenStax::Aws::Secrets.new(
        region: region,
        dry_run: dry_run,
        namespace: [env_name!, secrets_namespace(id: id)]
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

    def secrets_namespace(id: 'default')
      raise "Override this method in your deployment class and provide a namespace " \
            "for secrets data in the AWS Parameter Store.  The key there will be this namespace " \
            "prefixed by the environment name and suffixed with the secret name."
    end

  end
end
