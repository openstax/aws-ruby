module OpenStax::Aws
  class AutoScalingGroup
    attr_reader :raw_asg, :region

    delegate_missing_to :@raw_asg

    def self.physical_resource_id_attribute
      :name
    end

    def initialize(name:, region:)
      @raw_asg = Aws::AutoScaling::AutoScalingGroup.new(
        name: name,
        client: Aws::AutoScaling::Client.new(region: region)
      )
      @region = region
    end

    def increase_desired_capacity(by:)
      # take the smaller of max size or desired+by (or this call raises an exception)
      increase_to = [raw_asg.max_size, raw_asg.desired_capacity + by].min

      raw_asg.set_desired_capacity(
        {
          desired_capacity: increase_to
        })
    end

    def desired_capacity
      raw_asg.desired_capacity
    end

    def alarms
      client.describe_policies(
        auto_scaling_group_name: raw_asg.name
      ).flat_map(&:scaling_policies).flat_map(&:alarms).map do |alarm|
        OpenStax::Aws::Alarm.new region: region, name: alarm.alarm_name
      end
    end

    def add_tags_not_handled_by_cloudformation(stack_tags)
      alarms.each { |alarm| alarm.add_tags_not_handled_by_cloudformation stack_tags }
    end
  end
end
