module OpenStax::Aws
  class MskCluster

    attr_reader :client, :cluster_arn

    delegate_missing_to :@client

    def initialize(cluster_arn:, region:)
      @cluster_arn = cluster_arn
      @client = ::Aws::Kafka::Client.new(region: region)
    end

    def bootstrap_broker_string
      client.get_bootstrap_brokers(cluster_arn: cluster_arn).bootstrap_broker_string
    end

    def sorted_bootstrap_broker_string
      bootstrap_broker_string.split(',').sort.join(',')
    end

  end
end

