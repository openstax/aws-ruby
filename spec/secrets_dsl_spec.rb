require 'spec_helper'
require 'vcr_helper'

RSpec.describe 'secrets DSL', vcr: VCR_OPTS do

  let(:region) { 'us-east-2' }
  let(:env_name) { 'openstax-aws-ruby-secrets' }
  let(:namespace) { 'secrets-dsl-spec/main' }

  before(:each) {
    @logger = spy("logger")

    OpenStax::Aws.configure do |config|
      config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
      config.cfn_template_bucket_region = "us-west-2"
      config.stack_waiter_delay = vcr_recording? ? 5 : 0
      config.logger = vcr_recording? ? Logger.new(STDERR) : @logger
    end

    allow_any_instance_of(OpenStax::Aws::Template).to receive(:s3_folder) { "spec-templates" }
  }

  it 'creates secrets when stack created and deletes when deleted' do
    deployment = SecretsDslSpec::Deployment.new(env_name: env_name, region: region, dry_run: false)
    deployment.create(some_sha: "1b2ebfd91dd9fb34d58c834cbb70a21c6479ba8e", bucket_name: "aws-ruby-spec-secrets-dsl-create")

    expect_secrets_in_parameter_store({
      "random" => /[a-z0-9]{4}/,
      "interpolated" => "https://something-deployment-specific",
      "for_shared_substitution" => "howdy y'all",
      "content_key" => "something-deployment-specific",
      "more_secrets" => "foo"
    })

    deployment.delete

    expect(secrets.data).to be_empty
  end

  it 'updates secrets when stack updated' do
    deployment = SecretsDslSpec::Deployment.new(env_name: env_name, region: region, dry_run: false)
    deployment.create(some_sha: "1b2ebfd91dd9fb34d58c834cbb70a21c6479ba8e", bucket_name: "aws-ruby-spec-secrets-dsl-create")

    expect_secrets_in_parameter_store({
      "for_shared_substitution" => "howdy y'all",
    })

    deployment.value_to_change_before_update = "you'all"

    # The one value that changes above and a random value
    expect_any_instance_of(Aws::SSM::Client).to receive(:put_parameter).exactly(2).times.and_call_original

    deployment.update

    expect_secrets_in_parameter_store({
      "for_shared_substitution" => "howdy you'all",
    })

    expect(deployment.main_stack.deployed_parameters[:cycle_if_different]).to match /[a-f0-9]{20}/

    deployment.delete

    expect(secrets.data).to be_empty
  end

  def expect_secrets_in_parameter_store(expected_hash)
    actual_hash = secrets.data

    expected_hash.each do |key, value|
      expect(actual_hash["/#{env_name}/#{namespace}/#{key}"][:value]).to match value
    end
  end

  def secrets
    OpenStax::Aws::Secrets.new(env_name: env_name, namespace: namespace, region: region)
  end

end
