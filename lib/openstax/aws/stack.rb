module OpenStax::Aws
  class Stack

    attr_reader :name, :template, :dry_run, :capabilities,
                :enable_termination_protection, :region, :parameter_defaults,
                :volatile_parameters

    def initialize(name:, region:, enable_termination_protection: false,
                   absolute_template_path: nil,
                   capabilities: nil, parameter_defaults: {},
                   volatile_parameters: nil,
                   dry_run: true)
      @name = name
      @region = region || raise("region is not set for stack #{name}")
      @enable_termination_protection = enable_termination_protection

      @template = OpenStax::Aws::Template.new(absolute_file_path: absolute_template_path)

      set_capabilities(capabilities)
      @parameter_defaults = parameter_defaults.dup.freeze
      @volatile_parameters = volatile_parameters

      @dry_run = dry_run
    end

    def create(params: {}, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      params = parameter_defaults.merge(params)

      options = {
        stack_name: name,
        template_url: template.s3_url,
        capabilities: capabilities,
        parameters: self.class.format_hash_as_stack_parameters(params),
        enable_termination_protection: enable_termination_protection
      }

      logger.info("Creating #{name} stack...")
      client.create_stack(options) if !dry_run

      wait_for_creation if wait
    end

    def parameters_for_update(overrides: {})
      parameters = {}

      # Find parameters in the template we'll use for the update and for any
      # that

      # Start populating the parameters hash by using `:use_previous_value` for any
      # parameter that is currently in the template that is also currently on the stack,
      # and using the defined default value for any other parameter.

      existing_parameter_keys = existing_parameters.keys.map(&:to_sym)
      update_parameter_keys = template.parameter_names.map(&:underscore).map(&:to_sym)

      update_parameter_keys.each do |update_parameter_key|
        parameters[update_parameter_key] =
          if existing_parameter_keys.include?(update_parameter_key)
            :use_previous_value
          else
            parameter_defaults[update_parameter_key]
          end
      end

      # Volatile parameters can be changed outside of cloudformation updates.  Here
      # we get their current values by executing the block in the context of this
      # stack, and then we merge them in (overwriting any values already in the
      # parameters hash).

      realized_volatile_parameters = instance_eval(&volatile_parameters)
      parameters.merge!(realized_volatile_parameters)

      # Lastly, we merge in the overrides hash (e.g. things purposefully set
      # by an outside caller) -- they take precendence over all previous values.

      parameters.merge!(overrides)

      # Leave out nil-valued parameters as they are not valid (and likely not
      # intentional)
      parameters.compact
    end

    def existing_parameters
      aws_stack.parameters.each_with_object({}) do |parameter, hash|
        hash[parameter.parameter_key.underscore.to_s] = parameter.parameter_value
      end
    end

    def apply_change_set(params: {}, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      params = parameters_for_update(overrides: params)

      options = {
        stack_name: name,
        template_url: template.s3_url,
        capabilities: capabilities,
        parameters: self.class.format_hash_as_stack_parameters(params),
        change_set_name: "#{name}-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}"
      }

      create_change_set_output = client.create_change_set(options)
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

      wait_for_update if wait
    end

    def delete(wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      logger.info("Deleting #{name} stack...")

      client.delete_stack(stack_name: name) if !dry_run

      wait_for_deletion if wait
    end

    def output_value(key:)
      if dry_run
        "undefined-in-dry-run"
      else
        output = aws_stack.outputs.find {|output| output.output_key == key}
        raise "No output with key #{key} in stack #{name}" if output.nil?
        output.output_value
      end
    end

    def wait_for_creation
      wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackCreateComplete,
                           word: "created") if !dry_run
    end

    def wait_for_update
      wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackUpdateComplete,
                           word: "updated") if !dry_run
    end

    def wait_for_deletion
      wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackDeleteComplete,
                           word: "deleted") if !dry_run
    end

    def self.format_hash_as_stack_parameters(params={})
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

    protected

    def wait_for_stack_event(waiter_class:, word:)
      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for #{name} stack to be #{word}"
      )

      begin
        waiter_class.new(
          client: client,
          before_attempt: ->(*) { wait_message.say_it },
          delay: OpenStax::Aws.configuration.stack_waiter_delay
        ).wait(stack_name: name)
      rescue Aws::Waiters::Errors::WaiterFailed => error
        logger.error("Waiting failed: #{error.message}")
        raise
      end
      logger.info "#{name} has been #{word}!"
    end

    def wait_for_change_set_ready(change_set_name_or_id:)
      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for change set #{change_set_name_or_id} to be ready"
      )

      begin
        client.wait_until(:change_set_create_complete, change_set_name: change_set_name_or_id) do |w|
          w.delay = OpenStax::Aws.configuration.stack_waiter_delay
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

    SHORT_CAPABILITIES = {
      iam: "CAPABILITY_IAM",
      named_iam: "CAPABILITY_NAMED_IAM",
      auto_expand: "CAPABILITY_AUTO_EXPAND"
    }.freeze

    def set_capabilities(capabilities)
      capabilities ||= begin
        if OpenStax::Aws.configuration.infer_stack_capabilities
          template.required_capabilities
        else
          []
        end
      end

      capabilities = [capabilities].flatten.compact

      valid_capabilities = SHORT_CAPABILITIES.keys + SHORT_CAPABILITIES.values

      capabilities.each do |capability|
        if !valid_capabilities.include?(capability)
          raise "Capabilities must be in #{valid_capabilities}"
        end
      end

      @capabilities = capabilities.map do |capability|
        SHORT_CAPABILITIES[capability] || capability
      end.freeze
    end

    def logger
      OpenStax::Aws.configuration.logger
    end

    def aws_stack
      ::Aws::CloudFormation::Stack.new(name: name, client: client)
    end

    def client
      @client ||= ::Aws::CloudFormation::Client.new(region: region)
    end

  end
end
