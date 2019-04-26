module OpenStax::Aws
  class Stack

    attr_reader :name, :template, :dry_run, :capabilities,
                :is_production, :region, :default_parameters

    SHORT_CAPABILITIES = {
      iam: "CAPABILITY_IAM",
      named_iam: "CAPABILITY_NAMED_IAM",
      auto_expand: "CAPABILITY_AUTO_EXPAND"
    }.freeze

    def initialize(name:, region:, is_production: false,
                   template_namespace:, absolute_template_path:, capabilities: [],
                   dry_run: true, default_parameters: {})
      @region = region
      @is_production = is_production
      @name = name
      @template = OpenStax::Aws::Template.new(
        absolute_file_path: absolute_template_path,
        namespace: template_namespace
      )
      @dry_run = dry_run
      @capabilities = [capabilities].flatten.compact.map do |entry|
        SHORT_CAPABILITIES.keys.include?(entry) ? SHORT_CAPABILITIES[entry] : entry
      end.freeze
      @default_parameters = default_parameters.dup.freeze
    end

    def create(params: {}, enable_termination_protection: nil, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

      params = default_parameters.merge(params)

      options = {
        stack_name: name,
        template_url: template.s3_url,
        capabilities: capabilities,
        parameters: self.class.format_hash_as_stack_parameters(params),
      }

      # Default termination protection to on for production unless otherwise specified
      options[:enable_termination_protection] =
        if enable_termination_protection.nil?
          is_production
        else
          enable_termination_protection
        end

      logger.info("Creating #{name} stack...")
      client.create_stack(options) if !dry_run

      wait_for_creation if wait
    end

    def apply_change_set(params: {}, wait: false)
      logger.info("**** DRY RUN ****") if dry_run

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
