require 'spec_helper'

RSpec.describe OpenStax::Aws::MskCluster do
  let(:instance) { described_class.new(msk_instance_identifier: 'foo', region: 'us-east-1') }

  it 'Retrieves list of bootstrap hosts' do
      expect(instance.client).to receive(:get_bootstrap_brokers).with(cluster_arn: 'foo')
    instance.bootstrap_hosts
  end
end
