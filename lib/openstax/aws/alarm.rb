module OpenStax::Aws
  class Alarm
    attr_reader :raw_alarm

    delegate_missing_to :@raw_alarm

    def self.physical_resource_id_attribute
      :name
    end

    def initialize(region:, name:)
      @raw_alarm = ::Aws::CloudWatch::Alarm.new(
        name: name,
        client: Aws::CloudWatch::Client.new(region: region)
      )
    end

    def tags
      client.list_tags_for_resource(resource_arn: raw_alarm.alarm_arn).tags
    end

    def tag_resource(new_tags)
      client.tag_resource resource_arn: raw_alarm.alarm_arn, tags: new_tags
    end

    def logger
      OpenStax::Aws.configuration.logger
    end

    def add_tags_not_handled_by_cloudformation(stack_tags)
      missing_tags = stack_tags.map(&:to_h) - tags.map(&:to_h)

      return if missing_tags.empty?

      logger.debug "Tagging #{name}..."
      attempt = 1
      begin
        tag_resource missing_tags
      rescue Aws::CloudWatch::Errors::Throttling
        retry_in = attempt**2
        logger.debug "Tagging #{name} failed... retrying in #{retry_in} seconds"
        sleep retry_in
        attempt += 1
        retry
      end
    end
  end
end
