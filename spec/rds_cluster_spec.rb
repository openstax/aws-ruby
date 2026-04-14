require 'spec_helper'

RSpec.describe OpenStax::Aws::RdsCluster do
  let(:cluster) { described_class.new(db_cluster_identifier: "foo", region: "us-east-1") }

  it "changes the master password" do
    expect(cluster.raw).to receive(:modify).with({apply_immediately: true, master_user_password: "bar"})
    cluster.set_master_password(password: "bar")
  end
end
