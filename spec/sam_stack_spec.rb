require 'spec_helper'

RSpec.describe OpenStax::Aws::SamStack do

  context "#format_hash_as_cli_stack_parameters" do
    it "works" do
      expect(
        described_class.format_hash_as_cli_stack_parameters({a: "A", b_b: "B"})
      ).to eq "'ParameterKey=A,ParameterValue=A' 'ParameterKey=BB,ParameterValue=B'"
    end
  end

  context "#format_tags_as_cli_tags" do
    it "works" do
      expect(
        described_class.format_tags_as_cli_tags([OpenStax::Aws::Tag.new(:a, "A"), OpenStax::Aws::Tag.new(:b, "B")])
      ).to eq "'a=A' 'b=B'"
    end
  end

  context "#build" do
    let(:stack) { new_sam_stack }

    it "uses the right command" do
      expect(OpenStax::Aws::System).to receive(:call).with(
        "sam build -t #{stack.absolute_template_path} -b /tmp", any_args
      )

      stack.build
    end
  end

  context "#deploy" do
    context "deploy with tags" do
      let(:stack) do
        new_sam_stack(overrides: {
          tags: {Application: "Coolness", Project: "Oh yeah"},
          parameter_defaults: {EnvName: "env"}
        })
      end

      context "no parameters" do
        it "gives a good command" do
          expect(OpenStax::Aws::System).to receive(:call).with(
            / --tags 'Application=Coolness' 'Project=Oh yeah'/,
            any_args
          )

          stack.deploy(bucket_name: "foo")
        end
      end

      context "with parameters" do
        it "gives a good command with params" do
          expect(OpenStax::Aws::System).to receive(:call).with(
            / --parameter-overrides 'ParameterKey=EnvName,ParameterValue=env' 'ParameterKey=Foo,ParameterValue=Bar'/,
            any_args
          )

          stack.deploy(bucket_name: "foo", params: {Foo: "Bar"})
        end
      end
    end

    context "deploy without tags or params" do
      let(:stack) { new_sam_stack }

      it "gives a good command" do
        expect(OpenStax::Aws::System).to receive(:call).with(
          "sam deploy --template-file /tmp/template.yaml" \
          " --capabilities CAPABILITY_IAM" \
          " --s3-bucket some-bucket" \
          " --s3-prefix stackname" \
          " --stack-name stackname",
          any_args
        )

        stack.deploy(bucket_name: "some-bucket")
      end

      it "objects if tags are missing" do
        require_these_tags(%w(Foo))
        expect{
          stack.deploy(bucket_name: "some-bucket")
        }.to raise_error(/tag is required .* but is blank/)
      end
    end
  end

  def new_sam_stack(name: "stackname", filename: "sam_simple.yml", region: SPEC_DEFAULT_REGION, overrides: {})
    OpenStax::Aws::SamStack.new(
      {
        name: name,
        region: region,
        absolute_template_path: File.join(__dir__, "support/#{filename}"),
        dry_run: false,
        build_directory: '/tmp'
      }.merge(overrides)
    )
  end
end
