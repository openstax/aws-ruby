module OpenStax::Aws
  class DeploymentBase
    class Status
      def initialize(deployment)
        @deployment = deployment
      end

      def stack_statuses(reload: false)
        @deployment.stacks.each_with_object({}) do |stack, hash|
          hash[stack.name] = stack.status(reload: reload)
        end
      end

      def failed?(reload: false)
        stack_statuses(reload: reload).values.any?(&:failed?)
      end

      def succeeded?(reload: false)
        stack_statuses(reload: reload).values.all?(&:succeeded?)
      end

      def to_h
        {
          stacks: stack_statuses.each_with_object({}) do |(stack_name, stack_status), new_hash|
            new_hash[stack_name] = stack_status.to_h # convert the stack status object to a hash
          end
        }
      end

      def to_json
        to_h.to_json
      end
    end

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

      if @env_name && !@env_name.match(/^[a-zA-Z][a-zA-Z0-9-]*$/)
        raise "The environment name must consist only of letters, numbers, and hyphens, " \
              "and must start with a letter."
      end

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

    def tags
      self.class.tags.each_with_object(HashWithIndifferentAccess.new) do |(key, value), hsh|
        hsh[key] = value.is_a?(Proc) ? instance_eval(&value) : value
      end
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

      def sam_build_directory(*directory_parts)
        if method_defined?("sam_build_directory")
          raise "Can only set buisam_build_directoryld_directory once per class definition"
        end

        define_method "sam_build_directory" do
          File.expand_path(File.join(*directory_parts))
        end
      end

      def secrets(id, &block)
        if id.blank?
          raise "The first argument to `secrets` must be a non-blank ID"
        end

        if !id.to_s.match(/^[a-zA-Z][a-zA-Z0-9_]*$/)
          raise "The first argument to `secrets` must consist only of letters, numbers, and underscores, " \
                "and must start with a letter."
        end

        if method_defined?("#{id}_secrets")
          raise "Can only define the `#{id}` secrets once per class definition"
        end

        if method_defined?("#{id}_stack")
          raise "Cannot define `#{id}` secrets because there is a stack with that ID"
        end

        define_method("#{id}_secrets") do |for_create_or_update: false|
          secrets_factory = SecretsFactory.new(
            region: region,
            namespace: [env_name, name],
            context: self,
            dry_run: dry_run,
            for_create_or_update: for_create_or_update,
            shared_substitutions_block: @shared_secrets_substitutions_block
          )

          secrets_factory.namespace(id)
          secrets_factory.instance_exec({}, &block)
          secrets_factory.instance
        end
      end

      def stack_ids
        @stack_ids ||= []
      end

      def stack(id, &block)
        if id.blank?
          raise "The first argument to `stack` must be a non-blank ID"
        end

        if !id.to_s.match(/^[a-zA-Z][a-zA-Z0-9_]*$/)
          raise "The first argument to `stack` must consist only of letters, numbers, and underscores, " \
                "and must start with a letter."
        end

        if method_defined?("#{id}_secrets")
          raise "Cannot define `#{id}` stack because there are secrets with that ID"
        end

        stack_ids.push(id)

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
              defaults = parameter_defaults_from_template(stack_factory.absolute_template_path)
              defaults.each{|key,value| stack_factory.parameter_defaults[key] ||= value}
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

      def tag(key, value=nil, &block)
        raise 'The first argument to `tag` must not be blank' if key.blank?
        raise '`tag` must be given a value or a block' if value.nil? && !block_given?
        tags[key] = block_given? ? block : value
      end

      def tags
        @tags ||= HashWithIndifferentAccess.new
      end

      def inherited(child_class)
        # Copy any tags defined in the parent to the child so that it can access them
        # while not using class variables that are shared across all classes in the
        # that inherit here
        child_class.instance_variable_set("@tags", tags.dup)
      end

      def logger
        OpenStax::Aws.configuration.logger
      end
    end

    def parameter_defaults_from_template(template_or_absolute_template_path)
      template = template_or_absolute_template_path.is_a?(String) ?
                   Template.from_absolute_file_path(template_or_absolute_template_path) :
                   template_or_absolute_template_path

      template.parameter_names.each_with_object({}) do |parameter_name, defaults|
        value = parameter_default(parameter_name) ||
                built_in_parameter_default(parameter_name)

        if !value.nil?
          defaults[parameter_name.underscore.to_sym] = value
        end
      end
    end

    def stacks
      self.class.stack_ids.map{|id| self.send("#{id}_stack")}
    end

    def status(reload: false)
      @status = nil if reload
      @status ||= Status.new(self)
    end

    def deployed_parameters
      stacks.each_with_object({}) do |stack, hash|
        hash[stack.name] = stack.deployed_parameters
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

    def failed_statuses_table
      rows = []

      stacks.each do |stack|
        stack.status(reload: false).failed_events_since_last_user_event.each do |event|
          rows.push([stack.name, event.status_text, event.status_reason])
        end if stack.status.failed?
      end

      column_widths = [
        2 + rows.reduce(0) { |result, rowdata| [result, rowdata[0].length].max },
        2 + rows.reduce(0) { |result, rowdata| [result, rowdata[1].length].max },
        0
      ]

      output = []

      output.push(["Stack", "Status", "Reason"].each_with_index.map { |header, index| header.ljust(column_widths[index]) }.join(''))

      rows.each { |rowdata|
        output.push(rowdata.each_with_index.map { |value, index| value.ljust(column_widths[index]) }.join(''))
      }

      output.join("\n")
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

    def wait_for_tag_change(resource:, key:, polling_seconds: 20, timeout_seconds: nil)
      keep_polling = true
      started_at = Time.now
      original_value = resource_tag_value(resource: resource, key: key)

      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for the #{key} tag on #{resource.name} to change from #{original_value}"
      )

      while keep_polling
        wait_message.say_it

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

    def secrets_namespace(id: 'default')
      raise "Override this method in your deployment class and provide a namespace " \
            "for secrets data in the AWS Parameter Store.  The key there will be this namespace " \
            "prefixed by the environment name and suffixed with the secret name."
    end

    def log_and_exit_if_failed_status
      begin
        yield
      rescue
        if status.failed?
          logger.fatal("The following errors have occurred: \n#{failed_statuses_table}")
          exit(1)
        else
          raise
        end
      end
    end

  end
end
