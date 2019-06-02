require 'spec_helper'
require 'vcr_helper'

RSpec.describe 'secrets DSL', vcr: VCR_OPTS do

  let(:region) { 'us-east-2' }
  let(:env_name) { 'openstax-aws-ruby-secrets' }
  let(:namespace) { 'secrets-dsl-spec' }

  before(:each) {
    @logger = spy("logger")

    OpenStax::Aws.configure do |config|
      config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
      config.cfn_template_bucket_region = "us-west-2"
      config.stack_waiter_delay = vcr_recording? ? 5 : 0
      config.logger = @logger
    end

    allow_any_instance_of(OpenStax::Aws::Template).to receive(:s3_folder) { "spec-templates" }
  }

  it 'creates secrets when stack created and deletes when deleted' do
    deployment = SecretsDslSpec::Deployment.new(env_name: env_name, region: region, dry_run: false)
    deployment.create(some_sha: "356cd2ac1c04e693f649645f71d3590e24420563", bucket_name: "aws-ruby-spec-secrets-dsl-create")

    expect_secrets_in_parameter_store({
      "random" => /[a-z0-9]{8}/,
      "interpolated" => "https://something-deployment-specific"
    })

    deployment.delete

    expect(secrets.data).to be_empty
  end

  it 'updates secrets when stack updated' do

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