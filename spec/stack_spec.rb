require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::Stack, vcr: VCR_OPTS do

  let(:region) { SPEC_DEFAULT_REGION }

  before(:each) {
    @logger = spy("logger")

    OpenStax::Aws.configure do |config|
      config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
      config.cfn_template_bucket_region = "us-west-2"
      config.stack_waiter_delay = vcr_recording? ? 5 : 0
      config.logger = @logger
      config.fixed_s3_template_folder = "spec-templates"
    end
  }

  let(:bucket_name) { "aws-ruby-rspec-bucket" }

  it 'is ok deleting a stack that does not exist' do
    name = "spec-aws-ruby-stack-delete-non-existing"
    stack = new_template_one_stack(name: name)
    expect{stack.delete(wait: true)}.not_to raise_error
  end

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

  it 'creates a stack with tags' do
    name = "spec-aws-ruby-stack-create-tags"
    stack = new_stack(name: name, filename: "templates/simple.yml", overrides: {tags: {foo: "bar"}})
    stack.create(params: {}, wait: true)

    tags = ::Aws::CloudFormation::Stack.new(name: name, client: cfn_client).tags
    expect(tags[0].key).to eq "foo"
    expect(tags[0].value).to eq "bar"
  end

  it 'updates a stack with new tag values' do
    name = "spec-aws-ruby-stack-update-tags"
    stack = new_stack(name: name, filename: "templates/simple.yml", overrides: {tags: {foo: "bar"}})
    stack.create(params: {}, wait: true)

    stack = new_stack(name: name, filename: "templates/simple.yml", overrides: {tags: {foo: "howdy"}})
    stack.apply_change_set(params: {}, wait: true)

    tags = ::Aws::CloudFormation::Stack.new(name: name, client: cfn_client).tags
    expect(tags[0].key).to eq "foo"
    expect(tags[0].value).to eq "howdy"
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
    max_attempts = OpenStax::Aws.configuration.stack_waiter_max_attempts

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    expect(max_attempts).to be_an(Integer)
    expect(Aws::CloudFormation::Waiters::StackUpdateComplete).to receive(:new).with(hash_including(
      :max_attempts => max_attempts
    )).and_call_original

    stack.apply_change_set(params: {bucket_name: :use_previous_value, tag_value: "there"}, wait: true)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq "there"

    stack.delete
  end

  it "reverts to previous change set and template" do
    name = "spec-aws-ruby-stack-reverts-previous-change-set-and-template"
    tag_1 = "howdy"
    tag_2 = "there"
    template_from_file = File.read(File.join(__dir__, "support/templates/template_one.yml"))
    template_from_file_mod = File.read(File.join(__dir__, "support/templates/template_one_mod.yml"))

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: tag_1}, wait: true)

    stack = new_template_one_mod_stack(name: name)
    stack.apply_change_set(params: {bucket_name: :use_previous_value, tag_value: tag_2}, wait: true)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq tag_2

    template_from_aws = cfn_client.get_template({stack_name: name}).template_body
    expect(template_from_aws).to eq template_from_file_mod

    stack.revert_to_previous_change_set(wait: true)

    taggings = s3_client.get_bucket_tagging(bucket: bucket_name)
    expect(taggings.tag_set[0].value).to eq tag_1

    template_from_aws_after_revert = cfn_client.get_template({stack_name: name}).template_body
    expect(template_from_aws_after_revert).to eq template_from_file

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

  it "is a no-op update with no changes" do
    name = "spec-aws-ruby-stack-update-no-changes"

    stack = new_template_one_stack(name: name)
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    expect(stack).not_to receive(:wait_for_stack_event).with(
      waiter_class: Aws::CloudFormation::Waiters::StackUpdateComplete,
      word: "updated"
    )

    change_set = stack.apply_change_set
    stack.wait_for_update

    expect(change_set).to be_a OpenStax::Aws::ChangeSet
    expect(@logger).to have_received(:info).with(/No changes detected, deleting/)

    stack.delete(wait: true)
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
                        filename: "templates/updating_parameters/orig.yml",
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
                        filename: "templates/updating_parameters/mod.yml",
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

  it "can get a existing stack's template without specifying a file" do
    name = "spec-aws-ruby-stack-existing-template"

    stack = new_template_one_stack(name: name)
    file_template_contents = stack.template.body
    stack.create(params: {bucket_name: bucket_name, tag_value: "howdy"}, wait: true)

    stack = described_class.new(name: name, region: region, dry_run: false)
    expect(stack.template.body).to eq file_template_contents

    stack.delete
  end

  context "#deployed_parameters" do
    it "returns empty for non-existent stack" do
      stack = new_template_one_stack(name: "doesnotmatter")
      expect(stack.deployed_parameters).to eq({})
    end
  end

  context "#delete" do
    it "does not explode when deleting a non-existent stack" do
      stack = new_template_one_stack(name: "doesnotmatter")
      expect(OpenStax::Aws.configuration.logger).to receive(:info).with(/as it does not exist/)
      expect{stack.delete}.not_to raise_error
    end
  end

  context "#query" do
    before do
      do_not_mask_list_stacks_for(/aws-ruby-rspec-query/)
      clear_required_tags!

      @stack_1 = create_simple_stack(name: "aws-ruby-rspec-query-1")
      @stack_2 = create_simple_stack(name: "aws-ruby-rspec-query-2")
      @stack_3 = create_simple_stack(name: "aws-ruby-rspec-query-3")
    end

    after do
      @stack_1.delete(wait: true)
      @stack_2.delete(wait: true)
      @stack_3.delete(wait: true)
    end

    it "queries selected stacks" do
      expect(described_class.query(regex: /aws-ruby-rspec.*/).map(&:name)).to contain_exactly(
        "aws-ruby-rspec-query-1", "aws-ruby-rspec-query-2", "aws-ruby-rspec-query-3"
      )
    end

    it "does not rerun queries unless asked to" do
      # Seems like AWS does its own caching so we can't be exact here.
      expect(Aws::CloudFormation::Client).to receive(:new).at_most(8).times.and_call_original

      described_class.query(regex: /aws-ruby-rspec.*/)                # 4 times
      described_class.query(regex: /aws-ruby-rspec.*/)                # 0 times - cached
      described_class.query(regex: /aws-ruby-rspec.*/, reload: true)  # 4 times
    end
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
    new_stack(name: name, filename: "templates/template_one.yml", overrides: overrides)
  end

  def new_template_one_mod_stack(name:, overrides: {})
    new_stack(name: name, filename: "templates/template_one_mod.yml", overrides: overrides)
  end

  def create_simple_stack(name:)
    new_stack(name: name, filename: "templates/simple.yml").tap do |stack|
      stack.create(params: {}, wait: true)
    end
  end

end
