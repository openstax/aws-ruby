require 'spec_helper'

RSpec.describe OpenStax::Aws::RdsInstance do
  let(:instance) { described_class.new(db_instance_identifier: "foo", region: "us-east-1") }

  it "changes the master password" do
    expect(instance.raw).to receive(:modify).with({apply_immediately: true, master_user_password: "bar"})
    instance.set_master_password(password: "bar")
  end
end
