module OpenStax::Aws
  class ResourceFactory
    # All classes listed here should implement the self.physical_resource_id method
    ALL_TYPES = {
      'AWS::AutoScaling::AutoScalingGroup' => OpenStax::Aws::AutoScalingGroup,
      'AWS::CloudWatch::Alarm' => OpenStax::Aws::Alarm,
      'AWS::Events::Rule' => OpenStax::Aws::EventRule,
      'AWS::RDS::DBInstance' => OpenStax::Aws::RdsInstance,
      'AWS::MSK::Cluster' => OpenStax::Aws::MskCluster
    }

    attr_reader :region, :types

    def initialize(region:, types: nil)
      @region = region
      @types = types.nil? ? ALL_TYPES : ALL_TYPES.select { |type, _| types.include? type }
    end

    def from_stack_resource_or_summary(stack_resource)
      klass = types[stack_resource.resource_type]
      return if klass.nil?

      klass.new(
        region: region,
        klass.physical_resource_id_attribute => stack_resource.physical_resource_id
      )
    end

    def from_stack_resource_or_summary!(stack_resource)
      from_stack_resource_or_summary(stack_resource).tap do |resource|
        raise "'#{stack_resource.resource_type}' is not yet implemented in `ResourceFactory`" \
          if resource.nil?
      end
    end
  end
end
