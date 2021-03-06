require 'spec_helper'

RSpec.describe OpenStax::Aws::StackFactory do

  it 'passes a basic smoke test' do
    context = OpenStruct.new(
      env_name: "foo",
      count: 2,
      tags: {}
    )

    allow(File).to receive(:read).with("/tmp/fake") { "" }

    stack = described_class.build(id: :bar, deployment: context) do
      name "something"
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

  it 'manages volatile parameters' do
    stack = described_class.build(id: :bar, deployment: mock_deployment) do
      name "something"
      capabilities [:iam]
      region 'us-east-1'
      template_directory __dir__, "support/templates"
      relative_template_path "one_iam_resource.yml"
      volatile_parameters do
        tag_value { region }
      end
    end

    allow(stack).to receive(:deployed_parameters) {{}}

    expect(stack.parameters_for_update).to eq ({
      tag_value: "us-east-1"
    })
  end

  it 'sets tags' do
    stack = described_class.build(id: :bar, deployment: mock_deployment) do
      name "something"
      region 'us-east-1'
      template_directory __dir__, "support/templates"
      relative_template_path "simple.yml"
      tag :foo, "bar"
    end

    expect(stack.tags).not_to be_empty
    tag = stack.tags.first
    expect(tag.key).to eq "foo"
    expect(tag.value).to eq "bar"
  end

  def mock_deployment
    OpenStruct.new(tags: {})
  end

end
