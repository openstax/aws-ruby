module OpenStax::Aws
  class EventRule
    attr_reader :raw_rule, :client

    delegate_missing_to :@raw_rule

    def self.physical_resource_id_attribute
      :name
    end

    def initialize(name:, region:)
      @client = Aws::EventBridge::Client.new region: region
      # There is no real rule wrapper in the SDK but the DescribeRuleResponse can be used
      @raw_rule = client.describe_rule name: name
    end

    def tags
      client.list_tags_for_resource(resource_arn: raw_rule.arn).tags
    end

    def tag_resource(new_tags)
      client.tag_resource resource_arn: raw_rule.arn, tags: new_tags
    end
  end
end
