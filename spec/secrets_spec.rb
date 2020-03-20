require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::Secrets, vcr: VCR_OPTS do

  let(:dry_run) { true }
  let(:instance) {
    described_class.new(region: 'us-east-2',
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

    it "generates rsa sso values" do
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

    context "interesting literals" do
      let(:dry_run) { false }

      it "can handle numerical literals" do
        expect{
          instance.build_secrets(substitutions: {}, specifications:
            OpenStax::Aws::SecretsSpecification.from_content(
              format: :yml,
              content: <<~CONTENT
                foo: 300
              CONTENT
            )
          )
        }.not_to raise_error
      end

      it "can handle literal arrays" do
        secrets = instance.build_secrets(substitutions: {}, specifications:
          OpenStax::Aws::SecretsSpecification.from_content(
            format: :yml,
            content: <<~CONTENT
              foo:
                - bar1
                - bar2
            CONTENT
          )
        )

        expect(secrets[0][:type]).to eq "StringList"
        expect(secrets[0][:value]).to eq "bar1,bar2"
      end
    end

    context "referential secrets" do
      let(:dry_run) { false }

      it 'can get value from another parameter' do
        with_temporary_parameter(name: "something", value: "booyah") do |parameter_name:, client:|
          built_secrets = instance.build_secrets(substitutions: {}, specifications:
            OpenStax::Aws::SecretsSpecification.from_content(
              format: :yml,
              content: <<~CONTENT
                refers_to: ssm(#{parameter_name})
              CONTENT
            )
          )

          expect(built_secrets[0][:value]).to eq "booyah"
        end
      end

      it 'can get value from another parameter via a substitution' do
        with_temporary_parameter(name: "something", value: "howdy") do |parameter_name:, client:|
          built_secrets = instance.build_secrets(
            substitutions: {
              a_substitution_name: parameter_name
            },
            specifications:
              OpenStax::Aws::SecretsSpecification.from_content(
                format: :yml,
                content: <<~CONTENT
                  refers_to: ssm(a_substitution_name)
                CONTENT
              )
          )

          expect(built_secrets[0][:value]).to eq "howdy"
        end
      end

      it "complains if can't find referenced parameter" do
        expect{
          instance.build_secrets(substitutions: {}, specifications:
            OpenStax::Aws::SecretsSpecification.from_content(
              format: :yml,
              content: <<~CONTENT
                refers_to: ssm(substitution_that_does_not_exist)
              CONTENT
            )
          )
        }.to raise_error /neither a literal/
      end

      it "keeps track of which secrets were encrypted" do
        with_temporary_parameter(name: "something", value: "secret!", type: "SecureString") do |parameter_name:, client:|
          built_secrets = instance.build_secrets(
            substitutions: {},
            specifications:
              OpenStax::Aws::SecretsSpecification.from_content(
                format: :yml,
                content: <<~CONTENT
                  refers_to: ssm(#{parameter_name})
                CONTENT
              )
          )

          expect(built_secrets[0][:type]).to eq "SecureString"
        end
      end

      it "can handle arrays with non-literals" do
        secrets = instance.build_secrets(substitutions: {howdy: "there"}, specifications:
          OpenStax::Aws::SecretsSpecification.from_content(
            format: :yml,
            content: <<~CONTENT
              foo:
                - "{{ howdy }}"
                - random(hex,4)
            CONTENT
          )
        )

        expect(secrets[0][:type]).to eq "StringList"
        expect(secrets[0][:value]).to match /there,[a-f0-9]{4}/
      end
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
      with_temporary_parameter(name: "described_parameter",
                               value: "booyah",
                               description: "Very descriptive") do |parameter_name:, client:|

        raw_parameter = client.get_parameter(name: parameter_name).parameter
        rop = OpenStax::Aws::Secrets::ReadOnlyParameter.new(raw_parameter, client)
        expect(rop[:description]).to eq "Very descriptive"
      end
    end

  end

  def with_temporary_parameter(name:, type: "String", value:, description: nil)
    begin
      name = name.starts_with?("/") ? name[1..-1] : name
      parameter_name = "/openstax-aws-ruby-rspec/#{name}"
      client = Aws::SSM::Client.new(region: "us-east-2")

      parameter = {
        name: parameter_name,
        type: type,
        value: value,
      }
      parameter[:description] = description if !description.nil?

      client.put_parameter(parameter)

      yield(parameter_name: parameter_name, client: client)
    ensure
      client.delete_parameters({names: [parameter_name]})
    end
  end

end
