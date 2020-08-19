module OpenStax::Aws
  class MskCluster

    attr_reader :client, :msk_instance_identifier

    delegate_missing_to :@client

    def initialize(msk_instance_identifier:, region:)
      @msk_instance_identifier = msk_instance_identifier
      @client = ::Aws::Kafka::Client.new(region: region)
    end

    def bootstrap_hosts()
      client.get_bootstrap_brokers(cluster_arn: msk_instance_identifier).bootstrap_broker_string
    end

  end
end

