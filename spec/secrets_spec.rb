require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::Secrets, vcr: VCR_OPTS do

  let(:dry_run) { true }
  let(:instance) {
    described_class.new(region: 'region',
                        dry_run: dry_run,
                        namespace: ['env_name', 'namespace'])
  }

  context "#build_secrets" do
    let(:specification) {
      OpenStax::Aws::SecretsSpecification.from_content(
        format: :yml,
        top_key: :production,
        content: <<~CONTENT
          production:
            site_info:
              flag1: "{{ flag1 }}"
              flag2: "{{ flag2 }}"
              rand1: random(base64,7)
        CONTENT
      )
    }

    it 'can handle a boolean false value' do
      built_parameters = nil

      expect{
        built_parameters = instance.build_secrets(
          specifications: specification,
          substitutions: {
            flag1: "false",
            flag2: false,
          }
        )
      }.not_to raise_error
    end

    it 'generates base64 random values' do
      built_secrets = instance.build_secrets(substitutions: {}, specifications:
        OpenStax::Aws::SecretsSpecification.from_content(
          format: :yml,
          content: <<~CONTENT
            rand: random(base64,7)
          CONTENT
        )
      )
      expect(built_secrets[0][:value]).to match(/[a-zA-Z0-9_-]{7}/)
    end
  end

  context "#changed_secrets" do
    it "counts a secret as changed if it didn't exist" do
      new_secret = {name: "foo", value: "bar"}
      expect(described_class.changed_secrets({}, [new_secret])).to contain_exactly(new_secret)
    end

    it "does not say a secret is changed if the value is the same" do
      existing_secrets = {foo: {value: "bar"}}
      new_secret = {name: "foo", value: "bar"}
      expect(described_class.changed_secrets(existing_secrets, [new_secret])).to be_empty
    end

    it "does not say a secret is changed if the value is different but generated from same spec" do
      existing_secrets = {foo: {value: "bar", description: "Generated with something"}}
      new_secret = {name: "foo", value: "new", description: "Generated with something"}
      expect(described_class.changed_secrets(existing_secrets, [new_secret])).to be_empty
    end

    it "does say a secret is changed if the value is generated from a different spec" do
      existing_secrets = {foo: {value: "bar", description: "Generated with something"}}
      new_secret = {name: "foo", value: "new", description: "Generated with something else"}
      expect(described_class.changed_secrets(existing_secrets, [new_secret])).to contain_exactly(new_secret)
    end
  end

  context "#update" do
    before(:each) do
      allow(instance).to receive(:data!) { {
        "foo" => OpenStax::Aws::Secrets::ReadOnlyParameter.new(nil, OpenStruct.new(type: "String", value: "bar"))
      } }
    end

    it "says an unchanged secret is changed if it is forced to" do
      expect(OpenStax::Aws.logger).to receive(:info).with(/DRY RUN/)
      expect(OpenStax::Aws.logger).to receive(:info).with(/Updating the following.*foo/)

      instance.update(
        specifications: OpenStax::Aws::SecretsSpecification.from_content(
          format: :yml,
          top_key: :production,
          content: <<~CONTENT
            production:
              foo: bar
          CONTENT
        ),
        force_update_these: [/foo/])
    end
  end

  context "ReadOnlyParameter" do

    it "can read the parameter's description" do
      begin
        parameter_name = "/openstax-aws-ruby-rspec/described_parameter"
        client = Aws::SSM::Client.new(region: "us-east-2")
        client.put_parameter({
          name: parameter_name,
          type: "String",
          value: "booyah",
          description: "Very descriptive"
        })

        raw_parameter = client.get_parameter(name: parameter_name).parameter

        rop = OpenStax::Aws::Secrets::ReadOnlyParameter.new(raw_parameter, client)

        expect(rop[:description]).to eq "Very descriptive"
      ensure
        client.delete_parameters({names: [parameter_name]})
      end
    end

  end

end
