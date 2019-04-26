require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::Stack, vcr: VCR_OPTS do

  let(:region) { "us-east-2" }

  before(:each) {
    @logger = spy("logger")

    OpenStax::Aws.configure do |config|
      config.hosted_zone_name = "sandbox.openstax.org"
      config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
      config.log_bucket_name = "openstax-sandbox-logs"
      config.key_pair_name = "openstax-sandbox-kp"
      config.stack_waiter_delay = vcr_recording? ? 5 : 0
      config.logger = @logger
    end
  }

  let(:bucket_name) { "aws-ruby-rspec-bucket" }

  it 'creates a stack with provided parameters, then deletes it' do
    name = "spec-aws-ruby-stack-create-delete"

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    expect(@logger).to have_received(:info).with(/Creating #{name} stack.../)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq "howdy"

    stack.delete(wait: true)

    expect(@logger).to have_received(:info).with(/Deleting #{name} stack.../)

    expect{
      cfn_client.describe_stacks({stack_name: name})
    }.to raise_error(Aws::CloudFormation::Errors::ValidationError, /does not exist/)
  end

  it "uses default parameters" do
    name = "spec-aws-ruby-stack-default-parameters"

    stack = new_template_one_stack(name: name, overrides: {
      default_parameters: {
        bucket_name: bucket_name,
        tag_value: "howdy"
      }
    })
    stack.create(wait: true)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq "howdy"

    stack.delete
  end

  it "gets output values" do
    name = "spec-aws-ruby-stack-output-values"

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    expect(stack.output_value(key: "BucketArn")).to eq "arn:aws:s3:::#{bucket_name}"

    stack.delete
  end

  it "can be updated with new parameters" do
    name = "spec-aws-ruby-stack-update-new-parameters"
    tag_1 = "howdy"
    tag_2 = "there"

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    stack.apply_change_set(params: {bucket_name: :use_previous_value, tag_value: "there"}, wait: true)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq "there"

    stack.delete
  end

  it "can be updated with a new template" do
    name = "spec-aws-ruby-stack-update-new-template"

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    stack = new_template_one_mod_stack(name: name)
    stack.apply_change_set(params: {bucket_name: :use_previous_value, tag_value: :use_previous_value}, wait: true)

    expect(stack.output_value(key: "BucketArnMod")).to eq "arn:aws:s3:::#{bucket_name}"

    stack.delete(wait: true)

    expect{
      cfn_client.describe_stacks({stack_name: name})
    }.to raise_error(Aws::CloudFormation::Errors::ValidationError, /does not exist/)
  end

  it "can create and delete in a dry run" do
    expect_any_instance_of(Aws::CloudFormation::Client).not_to receive(:create_stack)
    expect_any_instance_of(Aws::CloudFormation::Client).not_to receive(:delete_stack)

    name = "spec-aws-ruby-stack-create-delete-dry"

    stack = new_template_one_stack(name: name, overrides: {dry_run: true})
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)
    stack.delete(wait: true)

    expect(@logger).to have_received(:info).with(/DRY RUN/).twice
    expect(@logger).to have_received(:info).with(/Creating #{name} stack.../)
    expect(@logger).to have_received(:info).with(/Deleting #{name} stack.../)
  end

  def iam_client
    Aws::IAM::Client.new(region: region)
  end

  def cfn_client
    Aws::CloudFormation::Client.new(region: region)
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(region: region)
  end

  def new_template_one_stack(name:, overrides: {})
    described_class.new(
      {
        name: name,
        region: region,
        is_production: false,
        template_namespace: "spec",
        absolute_template_path: File.join(__dir__, 'support/template_one.yml'),
        capabilities: [:iam, :named_iam],
        dry_run: false,
      }.merge(overrides)
    )
  end

  def new_template_one_mod_stack(name:, overrides: {})
    described_class.new(
      {
        name: name,
        region: region,
        is_production: false,
        template_namespace: "spec",
        absolute_template_path: File.join(__dir__, 'support/template_one_mod.yml'),
        capabilities: [:iam, :named_iam],
        dry_run: false,
      }.merge(overrides)
    )
  end

end
