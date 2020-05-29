require 'spec_helper'

RSpec.describe OpenStax::Aws::DeploymentBase::Status do
  context "#failed?" do
    it "returns true when one of the stacks has a failed status" do
      mock_deployment = double(stacks: [mock_stack(failed: false), mock_stack(failed: true)])
      expect(described_class.new(mock_deployment)).to be_failed
    end

    it "returns false when none of the stacks has a failed status" do
      mock_deployment = double(stacks: [mock_stack(failed: false), mock_stack(failed: false)])
      expect(described_class.new(mock_deployment)).not_to be_failed
    end
  end

  def mock_status(failed: false)
    double("a status").tap do |status|
      allow(status).to receive(:failed?).and_return failed
    end
  end

  def mock_stack(name: "foo", failed: false)
    double("a stack", name: name).tap do |stack|
      allow(stack).to receive(:status).and_return mock_status(failed: failed)
    end
  end
end