module OpenStax::Aws
  class AutoScalingGroup
    attr_reader :raw_asg

    delegate_missing_to :@raw_asg

    def initialize(name:, region:)
      @raw_asg = Aws::AutoScaling::AutoScalingGroup.new(
        name: name,
        client: Aws::AutoScaling::Client.new(region: region)
      )
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
  end
end
