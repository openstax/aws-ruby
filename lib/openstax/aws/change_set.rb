module OpenStax::Aws
  class ChangeSet

    attr_reader :client

    def initialize(client:)
      @client = client
    end

    def create(options:)
      create_change_set_output = client.create_change_set(options)
      @id = create_change_set_output.id

      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for change set #{id} to be ready"
      )

      begin
        client.wait_until(:change_set_create_complete, change_set_name: id) do |w|
          w.delay = OpenStax::Aws.configuration.stack_waiter_delay
          w.before_attempt do |attempts, response|
            wait_message.say_it
          end
        end
      rescue Aws::Waiters::Errors::FailureStateError => ee
        if ee.response&.status_reason =~ /didn't contain changes/
          logger.info("No changes detected, deleting change set")
          delete
          return self
        else
          logger.error(ee.response.status_reason)
          raise
        end
      rescue Aws::Waiters::Errors::WaiterFailed => ee
        logger.error("An error occurred: #{ee.message}")
        raise
      end

      @description = client.describe_change_set(change_set_name: id)

      self
    end

    def created?
      @description.present?
    end

    def delete
      client.delete_change_set(change_set_name: id)
    end

    def execute
      client.execute_change_set(change_set_name: id)
    end

    def id
      @id || raise("ID isn't yet known!")
    end

    def description
      @description || raise("Description not set; create failed?")
    end

    def has_change_caused_by?(entity_name)
      description.changes.any? do |change|
        change.resource_change.details.any? do |detail|
          detail.causing_entity == entity_name
        end
      end
    end

    def parameter_value(parameter_name)
      description.parameters.select do |parameter|
        parameter.parameter_key == parameter_name
      end.first.parameter_value
    end

    def change_summaries
      summaries = description.changes.flat_map(&:resource_change).map do |change|
        summary = "#{change.action} '#{change.logical_resource_id}' (#{change.resource_type})"

        case change.action
        when "Modify"
          causes = change.details.map{|detail| [detail.change_source, detail.causing_entity].compact.join(":")}.join(", ")

          summary = "#{summary}: Replacement=#{change.replacement}; Due to change in #{change.scope}; Causes: #{causes}"
        end

        summary
      end
    end

    protected

    def logger
      OpenStax::Aws.configuration.logger
    end

  end
end
