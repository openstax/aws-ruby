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

  it "uses parameter defaults" do
    name = "spec-aws-ruby-stack-parameter-defaults"

    stack = new_template_one_stack(name: name, overrides: {
      parameter_defaults: {
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

  context "#parameters_for_update" do
    it "uses defaults, volatile, use_previous_value" do
      stack = new_stack(name: "spec-aws-ruby-stack-param-update",
                        filename: "updating_parameters/orig.yml",
                        overrides: {
                          parameter_defaults: {
                            will_go_away: "value1",
                            sticks_around: "value2",
                            volatile_value: "gonna_change"
                          },
                          volatile_parameters_block: Proc.new do
                            volatile_value { name } # the stack's name as a placeholder for stack-specific data
                          end
                        })
      stack.create(params: { sticks_around_no_default: "value3" }, wait: true)

      stack = new_stack(name: "spec-aws-ruby-stack-param-update",
                        filename: "updating_parameters/mod.yml",
                        overrides: {
                          parameter_defaults: {
                            will_go_away: "value1",
                            sticks_around: "value2",
                            added: "added value",
                            volatile_value: "gonna_change"
                          },
                          volatile_parameters_block: Proc.new do
                            volatile_value { name } # the stack's name
                          end
                        })

      # Here is where volatile_value could be changed manually on the tag value
      # so we don't want to just "use_previous_value" b/c that would be "gonna_change"

      parameters = stack.parameters_for_update(overrides: {sticks_around: "override"})

      expect(parameters).to eq({
        sticks_around: "override",
        added: "added value",
        sticks_around_no_default: :use_previous_value,
        volatile_value: "spec-aws-ruby-stack-param-update"
      })

      stack.delete
    end
  end

  it "can be created without an absolute_template_path" do
    expect{OpenStax::Aws::Stack.new(name: "foo", region: "us-east-2")}.not_to raise_error
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
    new_stack(name: name, filename: "template_one.yml", overrides: overrides)
  end

  def new_template_one_mod_stack(name:, overrides: {})
    new_stack(name: name, filename: "template_one_mod.yml", overrides: overrides)
  end

  def new_stack(name:, filename:, overrides: {})
    allow_any_instance_of(OpenStax::Aws::Template).to receive(:s3_folder) { "spec-templates" }

    described_class.new(
      {
        name: name,
        region: region,
        absolute_template_path: File.join(__dir__, "support/templates/#{filename}"),
        dry_run: false,
      }.merge(overrides)
    )
  end

end
