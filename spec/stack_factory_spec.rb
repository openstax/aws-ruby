require 'spec_helper'

RSpec.describe OpenStax::Aws::StackFactory do

  it 'passes a basic smoke test' do
    context = OpenStruct.new(
      env_name: "foo",
      count: 2
    )

    stack = described_class.build(id: :bar, parameter_context: context) do
      capabilities [:iam]
      region "us-east-1"
      absolute_template_path "/tmp/fake"
      parameter_defaults do
        env_name { env_name }
        desired_capacity { count }
      end
    end

    expect(stack.capabilities).to eq ["CAPABILITY_IAM"]
    expect(stack.parameter_defaults[:env_name]).to eq "foo"
    expect(stack.parameter_defaults[:desired_capacity]).to eq 2
  end

end
