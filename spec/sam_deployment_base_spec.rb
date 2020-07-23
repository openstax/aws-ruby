require 'spec_helper'

RSpec.describe OpenStax::Aws::SamDeploymentBase do

  context "#stack_name" do
    it "works" do
      app = described_class.new(env_name: "env", name: "howdy_there", region: nil, app: nil)
      expect(app.stack_name).to eq "env-howdy-there"
    end
  end

  context "#format_hash_as_cli_stack_parameters" do
    it "works" do
      expect(
        described_class.format_hash_as_cli_stack_parameters({a: "A", b: "B"})
      ).to eq "'ParameterKey=a,ParameterValue=A' 'ParameterKey=b,ParameterValue=B'"
    end
  end

  context "#format_hash_as_cli_tags" do
    it "works" do
      expect(
        described_class.format_hash_as_cli_tags({a: "A", b: "B"})
      ).to eq "'Key=a,Value=A' 'Key=b,Value=B'"
    end
  end

  context "#deploy" do
    let(:app) do
      Class.new(OpenStax::Aws::SamAppBase) do
        build_directory '/build'
      end.new
    end

    let(:deployment) do
      deployment_class.new(env_name: "env", region: "us-east-1", name: "coolness", app: app)
    end

    before do
      # fake the template file contents so it can find a bucket name
      allow(File).to receive(:read) { "\n\n\nCodeUri: s3://some-bucket/blah\n\n"}
    end

    context "deployment with tags" do
      let(:deployment_class) do
        Class.new(described_class) do
          tag :Application, "Coolness"
          tag :Project, "Oh yeah"
        end
      end

      it "gives a good command" do
        expect(OpenStax::Aws::System).to receive(:call).with(
          / --tags 'Key=Application,Value=Coolness' 'Key=Project,Value=Oh yeah'/,
          any_args
        )

        deployment.deploy
      end

      it "gives a good command with params" do
        expect(OpenStax::Aws::System).to receive(:call).with(
          / --parameter-overrides 'ParameterKey=Foo,ParameterValue=Bar'/,
          any_args
        )

        deployment.deploy(params: {Foo: "Bar"})
      end
    end

    context "deployment without tags" do
      let(:deployment_class) do
        Class.new(described_class)
      end

      it "gives a good command without params" do
        expect(OpenStax::Aws::System).to receive(:call).with(
          "sam deploy --template-file /build/app-output-sam.yaml" \
          " --capabilities CAPABILITY_IAM" \
          " --s3-bucket some-bucket" \
          " --s3-prefix env-coolness" \
          " --stack-name env-coolness",
          any_args
        )

        deployment.deploy
      end
    end
  end
end
