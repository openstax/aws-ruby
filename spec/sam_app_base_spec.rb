require 'spec_helper'

RSpec.describe OpenStax::Aws::SamAppBase do

  let(:vanilla_app) { Class.new(described_class).new }

  context "#packaged_template_filename" do
    it "has a default" do
      expect(vanilla_app.packaged_template_filename).to eq "app-output-sam.yaml"
    end

    it "can be overridden" do
      app_class = Class.new(described_class) do
        packaged_template_filename 'other.yaml'
      end
      expect(app_class.new.packaged_template_filename).to eq "other.yaml"
    end
  end

  context "#source_template_file" do
    it "must be explicitly defined" do
      expect{vanilla_app.source_template_file}.to raise_error(/must set the source/)
    end

    it "can bet set" do
      app_class = Class.new(described_class) do
        source_template_file '/Foo/bar', 'template.yaml'
      end
      expect(app_class.new.source_template_file).to eq "/Foo/bar/template.yaml"
    end
  end

  context "#build_directory" do
    it "must be explicitly defined" do
      expect{vanilla_app.build_directory}.to raise_error(/must set the build/)
    end

    it "can be set" do
      app_class = Class.new(described_class) do
        build_directory '/Foo/bar', '../howdy'
      end
      expect(app_class.new.build_directory).to eq "/Foo/howdy"
    end
  end

  context "#built_template_file" do
    it "works" do
      app_class = Class.new(described_class) do
        build_directory '/Foo'
      end
      expect(app_class.new.built_template_file).to eq "/Foo/template.yaml"
    end
  end

  context "#packaged_template_file" do
    it "works" do
      app_class = Class.new(described_class) do
        build_directory '/Foo'
      end
      expect(app_class.new.packaged_template_file).to eq "/Foo/app-output-sam.yaml"
    end
  end

  context "#build" do
    it "uses the right command" do
      app_class = Class.new(described_class) do
        build_directory '/Foo'
        source_template_file '/Bar/distribution.yml'
      end

      expect(OpenStax::Aws::System).to receive(:call).with(
        "sam build -t /Bar/distribution.yml -b /Foo", any_args
      )

      app_class.new.build
    end
  end

  context "#package" do
    it "uses the right command" do
      app_class = Class.new(described_class) do
        build_directory '/Foo'
      end

      expect(OpenStax::Aws::System).to receive(:call).with(
        "sam package --s3-bucket some_bucket" \
        " --template-file /Foo/template.yaml" \
        " --output-template-file /Foo/app-output-sam.yaml",
        any_args
      )

      app_class.new.package(bucket: "some_bucket")
    end
  end

end
