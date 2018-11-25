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

    def subdomain_with_trailing_dot(site_name:)
      parts = []
      parts.push(site_name) if !site_name.blank?
      parts.push(env_name!) if env_name! != "production" # production env_name is hidden

      subdomain = parts.join("-")
      subdomain.blank? ? "" : subdomain + "."
    end

    def build_domain(site_name:)
      "#{subdomain_with_trailing_dot(site_name: site_name)}#{hosted_zone_name}"
    end

    def hosted_zone_name
      OpenStax::Aws.configuration.hosted_zone_name
    end

    def stack_output_value(stack:, key:)
      output = stack.outputs.find {|output| output.output_key == key}
      raise "No output with key #{key} in stack #{stack}" if output.nil?
      output.output_value
    end

    def wait_for_stack_event(stack_name:, waiter_class:, word:)
      begin
        waiter_class.new(
          client: client,
          before_attempt: ->(*) { puts "Waiting for #{stack_name} stack to be #{word}...\n"}
        ).wait(stack_name: stack_name)
      rescue Aws::Waiters::Errors::WaiterFailed => error
        "Waiting failed: #{error.message}"
        raise
      end
      puts "#{stack_name} has been #{word}!"
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
      client.wait_until(:change_set_create_complete, change_set_name: change_set_name_or_id) do |w|
        w.delay = 10
        w.before_attempt do |attempts, response|
          puts "Waiting for Change Set #{change_set_name_or_id} to be ready...\n"
        end
      end
    end

    def apply_change_set(params:, dry_run: true)
      create_change_set_output = client.create_change_set(params)

      wait_for_change_set_ready(change_set_name_or_id: create_change_set_output.id)

      if dry_run
        pp client.describe_change_set(change_set_name: create_change_set_output.id)
      else
        puts "Executing Change Set\n"
        out = client.execute_change_set(change_set_name: create_change_set_output.id)
      end
    end

    def client
      @client ||= ::Aws::CloudFormation::Client.new(region: region)
    end

    def client_params(params={})
      params.map do |key, value|
        {
          parameter_key: key.to_s.split('_').collect(&:capitalize).join,
          parameter_value: value
        }
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

    def cfn_template_bucket
      @cfn_template_bucket ||= begin
        s3 = ::Aws::S3::Resource.new(region: region)
        s3.bucket(OpenStax::Aws.configuration.cfn_template_bucket_name)
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

    def upload_template(absolute_file_path:)
      file_name = File.basename(absolute_file_path)
      cfn_template_bucket.object("#{template_path(file_name: file_name)}").upload_file(absolute_file_path)
    end

    def template_url(file_name:)
      "https://s3.amazonaws.com/#{OpenStax::Aws.configuration.cfn_template_bucket_name}/#{template_path(file_name: file_name)}"
    end

    def template_path(file_name:)
      # e.g. "may5/interactions/app.yml"
      ["cfn_templates", env_name, name!, file_name].compact.join("/")
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

    def delete_stack(stack_name:)
      client.delete_stack(stack_name: stack_name)
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
