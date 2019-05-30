require 'spec_helper'

RSpec.describe OpenStax::Aws::AutoScalingGroup do
  let(:double_asg) { double(desired_capacity: 2) }

  subject(:asg) { described_class.new(name:'foo', region: 'bar') }

  before do
    allow(Aws::AutoScaling::AutoScalingGroup).to receive(:new).and_return(double_asg)
  end

  it 'creates the auto scaling group' do
    expect(double_asg).to receive(:set_desired_capacity).with({desired_capacity: 6})
    asg.increase_desired_capacity(by: 4)
  end
end
