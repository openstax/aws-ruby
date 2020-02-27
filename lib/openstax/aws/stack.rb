module OpenStax::Aws
  class Stack

    attr_reader :name, :application, :owner, :environment, :id, :absolute_template_path, :dry_run,
                :enable_termination_protection, :region, :parameter_defaults,
                :volatile_parameters_block, :secrets_blocks

    def initialize(id: nil, name:, application: '', owner: '', environment: '',
                   region:, enable_termination_protection: false,
                   absolute_template_path: nil,
                   capabilities: nil, parameter_defaults: {},
                   volatile_parameters_block: nil,
                   secrets_blocks: [], secrets_context: nil, secrets_namespace: nil,
                   shared_secrets_substitutions_block: nil,
                   cycle_if_different_parameter: nil,
                   dry_run: true)
      @id = id

      raise "Stack name must not be blank" if name.blank?
      @name = name

      raise "Stack application is used for tagging and must not be blank" if application.blank?
      @application = application

      raise "Stack owner is used for tagging and must not be blank" if owner.blank?
      @owner = owner

      raise "Stack environment is used for tagging and must not be blank" if environment.blank?
      @environment = environment

      @region = region || raise("region is not set for stack #{name}")
      @enable_termination_protection = enable_termination_protection

      @absolute_template_path = absolute_template_path

      set_capabilities(capabilities)
      @parameter_defaults = parameter_defaults.dup.freeze
      @volatile_parameters_block = volatile_parameters_block

      @secrets_blocks = [secrets_blocks].flatten.compact
      @secrets_context = secrets_context
      @secrets_namespace = secrets_namespace
      @shared_secrets_substitutions_block = shared_secrets_substitutions_block

      @cycle_if_different_parameter = (
        cycle_if_different_parameter ||
        OpenStax::Aws.configuration.default_cycle_if_different_parameter
      ).underscore.to_sym

      @dry_run = dry_run
    end

    def template
      @template ||= begin
        if absolute_template_path.present?
          OpenStax::Aws::Template.from_absolute_file_path(absolute_template_path)
        else
          body = client.get_template({stack_name: name}).template_body
          OpenStax::Aws::Template.from_body(body)
        end
      end
    end

    def create(params: {}, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      params = parameter_defaults.merge(params)

      if defines_secrets?
        logger.info("Creating #{name} stack secrets...")
        secrets(parameters: params, for_create_or_update: true).create
      end

      options = {
        stack_name: name,
        template_url: template.s3_url,
        capabilities: capabilities,
        parameters: self.class.format_hash_as_stack_parameters(params),
        enable_termination_protection: enable_termination_protection,
        tags: [
          {key: 'Application', value: @application},
          {key: 'Owner', value: @owner},
          {key: 'Environment', value: @environment},
        ]
      }

      logger.info("Creating #{name} stack...")
      client.create_stack(options) if !dry_run

      wait_for_creation if wait
    end

    def parameters_for_update(overrides: {})
      parameters = {}

      # Start populating the parameters hash by using `:use_previous_value` for any
      # parameter that is currently in the template that is also currently on the stack,
      # and using the defined default value for any other parameter.

      continuing_parameter_keys.each do |continuing_parameter_key|
        parameters[continuing_parameter_key] = :use_previous_value
      end

      new_parameter_keys.each do |new_parameter_key|
        parameters[new_parameter_key] = parameter_defaults[new_parameter_key]
      end

      # Volatile parameters can be changed outside of cloudformation updates.  Here
      # we get their current values by executing the block in the context of this
      # stack, and then we merge them in (overwriting any values already in the
      # parameters hash).

      parameters.merge!(volatile_parameters)

      # Lastly, we merge in the overrides hash (e.g. things purposefully set
      # by an outside caller) -- they take precendence over all previous values.

      parameters.merge!(overrides)

      # Leave out nil-valued parameters as they are not valid (and likely not
      # intentional)

      parameters.compact
    end

    def volatile_parameters
      return {} if volatile_parameters_block.nil?

      volatile_parameters_factory = StackFactory::VolatileParametersFactory.new(self)
      volatile_parameters_factory.instance_eval(&volatile_parameters_block)
      volatile_parameters_factory.attributes
    end

    def deployed_parameters
      begin
        @deployed_parameters ||= aws_stack.parameters.each_with_object({}) do |parameter, hash|
          hash[parameter.parameter_key.underscore.to_sym] = parameter.parameter_value
        end
      rescue Aws::CloudFormation::Errors::ValidationError => ee
        if ee.message =~ /Stack.*does not exist/
          {}
        else
          raise
        end
      end
    end

    def secrets(parameters: {}, for_create_or_update: false)
      SecretsSet.new(
        secrets_blocks.map do |secrets_block|
          secrets_factory = SecretsFactory.new(
            region: region,
            namespace: @secrets_namespace,
            context: @secrets_context,
            dry_run: dry_run,
            for_create_or_update: for_create_or_update,
            shared_substitutions_block: @shared_secrets_substitutions_block
          )

          secrets_factory.namespace(id)
          secrets_factory.instance_exec parameters, &secrets_block
          secrets_factory.instance
        end
      )
    end

    def create_change_set(options)
      OpenStax::Aws::ChangeSet.new(client: client).create(options: options)
    end

    def apply_change_set(params: {}, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      logger.info("Updating #{name} stack...")

      params = parameters_for_update(overrides: params)

      if defines_secrets?
        logger.info("Updating #{name} stack secrets...")

        secrets_changed = secrets(
          parameters: StackParameters.new(params: params, stack: self),
          for_create_or_update: true
        ).update

        if secrets_changed && template_parameter_keys.include?(@cycle_if_different_parameter)
          logger.info("Secrets changed, setting stack parameter to trigger server cycling")
          params[@cycle_if_different_parameter] = SecureRandom.hex(10)
        end
      end

      options = {
        stack_name: name,
        template_url: template.s3_url,
        capabilities: capabilities,
        parameters: self.class.format_hash_as_stack_parameters(params),
        change_set_name: "#{name}-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}"
      }

      change_set = create_change_set(options)

      if change_set.created?
        resource_changes = change_set.resource_change_summaries

        logger.info("#{resource_changes.size} resource change(s)#{':' if !resource_changes.empty?}")
        resource_changes.each do |resource_change|
          logger.debug(resource_change)
        end

        if dry_run
          logger.info("Deleting change set (because this is a dry run)")
          change_set.delete
        else
          logger.info("Executing change set")
          change_set.execute
          reset_cached_remote_state
        end

        wait_for_update if wait
      end

      change_set
    end

    def delete(wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      if defines_secrets?
        logger.info("Deleting #{name} stack secrets...")
        secrets.delete
      end

      logger.info("Deleting #{name} stack...")

      if exists?
        client.delete_stack(stack_name: name) if !dry_run
      else
        logger.info("Cannot delete #{name} stack as it does not exist")
      end

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
      if !dry_run
        return if !creating?
        wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackCreateComplete,
                             word: "created")
      end
    end

    def wait_for_update
      if !dry_run
        return if !updating? # if not updating, waiting for an updated message will thrash until timeout
        wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackUpdateComplete,
                             word: "updated")
      end
    end

    def wait_for_deletion
      if !dry_run
        begin
          return if !deleting?
          wait_for_stack_event(waiter_class: Aws::CloudFormation::Waiters::StackDeleteComplete,
                               word: "deleted")
        rescue Aws::CloudFormation::Errors::ValidationError => ee
          if ee.message =~ /Stack.*does not exist/
            logger.warn("Waiting for stack #{name} to be deleted failed because it does not exist")
          else
            raise
          end
        end
      end
    end

    def resource(logical_id)
      stack_resource = aws_stack.resource(logical_id)

      case stack_resource.resource_type
      when "AWS::AutoScaling::AutoScalingGroup"
        name = stack_resource.physical_resource_id
        client = Aws::AutoScaling::Client.new(region: region)
        Aws::AutoScaling::AutoScalingGroup.new(name: name, client: client)
      else
        raise "'#{stack_resource.resource_type}' is not yet implemented in `Stack#resource`"
      end
    end

    def capabilities
      set_capabilities(default_capabilities) if @capabilities.nil?
      @capabilities
    end

    def default_capabilities
      if OpenStax::Aws.configuration.infer_stack_capabilities
        template.required_capabilities
      else
        []
      end
    end

    def self.format_hash_as_stack_parameters(params={})
      params.map do |key, value|
        {
          parameter_key: key.to_s.split('_').collect(&:capitalize).join,
        }.tap do |hash|
          if value == :use_previous_value
            hash[:use_previous_value] = true
          else
            hash[:parameter_value] = value.to_s
          end
        end
      end
    end

    def status
      begin
        aws_stack.stack_status
      rescue Aws::CloudFormation::Errors::ValidationError => ee
        case ee.message
        when /Stack.*does not exist/
          "DOES_NOT_EXIST"
        else
          raise
        end
      end
    end

    def updating?
      %w(
        UPDATE_COMPLETE_CLEANUP_IN_PROGRESS
        UPDATE_IN_PROGRESS
        UPDATE_ROLLBACK_COMPLETE
        UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS
        UPDATE_ROLLBACK_FAILED
        UPDATE_ROLLBACK_IN_PROGRESS
      ).include?(status)
    end

    def creating?
      "CREATE_IN_PROGRESS" == status
    end

    def deleting?
      "DELETE_IN_PROGRESS" == status
    end

    def exists?
      "DOES_NOT_EXIST" != status
    end

    def defines_secrets?
      !secrets_blocks.empty?
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

    SHORT_CAPABILITIES = {
      iam: "CAPABILITY_IAM",
      named_iam: "CAPABILITY_NAMED_IAM",
      auto_expand: "CAPABILITY_AUTO_EXPAND"
    }.freeze

    def set_capabilities(capabilities)
      return if capabilities.nil?

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

    def template_parameter_keys
      @tpks ||= template.parameter_names.map(&:underscore).map(&:to_sym)
    end

    def continuing_parameter_keys
      template_parameter_keys & deployed_parameters.keys
    end

    def new_parameter_keys
      template_parameter_keys - continuing_parameter_keys
    end

    def reset_cached_remote_state
      @deployed_parameters = nil
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
