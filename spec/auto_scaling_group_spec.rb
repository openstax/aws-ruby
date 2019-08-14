require 'spec_helper'

RSpec.describe OpenStax::Aws::AutoScalingGroup do
  let(:max_size) { 10 }
  let(:double_asg) { double(desired_capacity: 2, max_size: max_size) }

  subject(:asg) { described_class.new(name:'foo', region: 'bar') }

  before do
    allow(Aws::AutoScaling::AutoScalingGroup).to receive(:new).and_return(double_asg)
  end

  it 'creates the auto scaling group' do
    expect(double_asg).to receive(:set_desired_capacity).with({desired_capacity: 6})
    asg.increase_desired_capacity(by: 4)
  end

  context "when target is greater than max" do
    let(:expected_param) { { desired_capacity: max_size} }

    it 'creates the auto scaling group' do
      expect(double_asg).to receive(:set_desired_capacity).with(expected_param)
      asg.increase_desired_capacity(by: 50)
    end
  end
end
