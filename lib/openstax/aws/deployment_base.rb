module OpenStax::Aws
  class DeploymentBase

    attr_reader :env_name, :region, :name

    RESERVED_ENV_NAMES = [
      "external", # used to namespace external secrets in the parameter store
    ]

    def initialize(env_name: nil, region:, name:)
      if RESERVED_ENV_NAMES.include?(env_name)
        raise "#{env_name} is a reserved word and cannot be used as an environment name"
      end

      # Allow a blank env_name but normalize it to `nil`
      @env_name = env_name.blank? ? nil : env_name
      @region = region
      @name = name
    end

    def name!
      raise "`name` is blank" if name.blank?
      name
    end

    def env_name!
      raise "`env_name` is blank" if env_name.blank?
      env_name
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

    def stack_output_value(stack:, key:)
      stack = stack(stack_name: stack) if stack.is_a?(String)

      output = stack.outputs.find {|output| output.output_key == key}
      raise "No output with key #{key} in stack #{stack}" if output.nil?
      output.output_value
    end

    def wait_for_stack_event(stack_name:, waiter_class:, word:)
      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for #{stack_name} stack to be #{word}"
      )

      begin
        waiter_class.new(
          client: client,
          before_attempt: ->(*) { wait_message.say_it }
        ).wait(stack_name: stack_name)
      rescue Aws::Waiters::Errors::WaiterFailed => error
        logger.error("Waiting failed: #{error.message}")
        raise
      end
      logger.info "#{stack_name} has been #{word}!"
    end

    def wait_for_stack_creation(stack_name:)
      wait_for_stack_event(stack_name: stack_name,
                           waiter_class: Aws::CloudFormation::Waiters::StackCreateComplete,
                           word: "created")
    end

    def wait_for_stack_deletion(stack_name:)
      wait_for_stack_event(stack_name: stack_name,
                           waiter_class: Aws::CloudFormation::Waiters::StackDeleteComplete,
                           word: "deleted")
    end

    def wait_for_change_set_ready(change_set_name_or_id:)
      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for change set #{change_set_name_or_id} to be ready"
      )

      begin
        client.wait_until(:change_set_create_complete, change_set_name: change_set_name_or_id) do |w|
          w.delay = 10
          w.before_attempt do |attempts, response|
            wait_message.say_it
          end
        end
      rescue Aws::Waiters::Errors::FailureStateError => ee
        logger.error(ee.response.status_reason)
        raise
      rescue Aws::Waiters::Errors::WaiterFailed => ee
        logger.error("An error occurred: #{ee.message}")
        raise
      end
    end

    def wait_for_stack_update(stack_name:)
      wait_for_stack_event(stack_name: stack_name,
                           waiter_class: Aws::CloudFormation::Waiters::StackUpdateComplete,
                           word: "updated")
    end

    def apply_change_set(params:, dry_run: true)
      logger.info("\n**** DRY RUN ****\n") if dry_run

      create_change_set_output = client.create_change_set(params)
      wait_for_change_set_ready(change_set_name_or_id: create_change_set_output.id)

      change_set_description = OpenStax::Aws::ChangeSetDescription.new(
        client.describe_change_set(change_set_name: create_change_set_output.id)
      )

      if dry_run
        logger.info("Deleting Change Set (because this is a dry run)")
        client.delete_change_set(change_set_name: create_change_set_output.id) # cleanup
      else
        logger.info("Executing Change Set")
        client.execute_change_set(change_set_name: create_change_set_output.id)
      end

      logger.info(change_set_description.change_summaries.join("\n"))

      change_set_description
    end

    def create_stack(params={})
      logger.info("Creating #{params[:stack_name]} stack...")

      # Default termination protection to on for production
      if is_production? && !params.has_key?(:enable_termination_protection)
        params[:enable_termination_protection] = true
      end

      client.create_stack(params)
    end

    def delete_stack(stack_name:)
      logger.info("Deleting #{stack_name} stack...")

      client.delete_stack(stack_name: stack_name)
    end

    def client
      @client ||= ::Aws::CloudFormation::Client.new(region: region)
    end

    def client_params(params={})
      params.map do |key, value|
        {
          parameter_key: key.to_s.split('_').collect(&:capitalize).join,
        }.tap do |hash|
          if value == :use_previous_value
            hash[:use_previous_value] = true
          else
            hash[:parameter_value] = value
          end
        end
      end
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

    def parameters
      @parameters ||= OpenStax::Aws::Parameters.new(
        region: region,
        env_name: env_name!,
        parameter_namespace: parameter_namespace
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

    def stack(stack_name:)
      ::Aws::CloudFormation::Stack.new(name: stack_name, client: client)
    end

    protected

    def parameter_namespace
      raise "Override this method in your deployment class and provide a namespace " \
            "for data in the AWS Parameter Store.  The parameter key will be this namespace " \
            "prefixed by the environment name and suffixed with the parameter name."
    end

  end
end
