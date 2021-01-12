# frozen_string_literal: true

require 'spec_helper'
require 'vcr_helper'

ACTUAL_MSK_ARN = 'arn:aws:kafka:us-east-2:373045849756:cluster/rjr-test-quasar/430c3363-00b0-4576-ae82-6894eb9ea401-3'
RSpec.describe OpenStax::Aws::MskCluster, vcr: VCR_OPTS do
  let(:instance) do
    described_class.new(
      cluster_arn: ACTUAL_MSK_ARN, region: 'us-east-2'
    )
  end

  it 'retrieves a csv string listing bootstrap hosts' do
    expect(instance.client).to receive(:get_bootstrap_brokers).with(cluster_arn: ACTUAL_MSK_ARN).and_call_original
    instance.bootstrap_broker_string
  end

  it 'retrieves a sorted csv string listing bootstrap hosts' do
    allow(instance).to receive(:bootstrap_broker_string).and_return("https://foo:9292,https://bar:8080")
    expect(instance.sorted_bootstrap_broker_string).to eq "https://bar:8080,https://foo:9292"
  end
end
