module OpenStax::Aws
  class Alarm
    attr_reader :raw_alarm

    delegate_missing_to :@raw_alarm

    def self.physical_resource_id_attribute
      :name
    end

    def initialize(region:, raw_alarm: nil, name: nil)
      raise ArgumentError, 'Must provide either raw_alarm or name' if raw_alarm.nil? && name.nil?

      @raw_alarm = raw_alarm || ::Aws::CloudWatch::Alarm.new(
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

    def add_tags_not_handled_by_cloudformation(stack_tags)
      missing_tags = stack_tags.map(&:to_h) - tags.map(&:to_h)

      return if missing_tags.empty?

      logger.debug "Tagging #{name}..."
      tag_resource missing_tags
    end
  end
end
