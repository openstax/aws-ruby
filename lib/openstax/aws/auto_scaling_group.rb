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
      raw_asg.set_desired_capacity(
        {
          desired_capacity: raw_asg.desired_capacity() + by
        })
    end

    def desired_capacity
      raw_asg.desired_capacity
    end
  end
end
