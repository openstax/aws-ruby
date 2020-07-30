require 'spec_helper'

RSpec.describe OpenStax::Aws::DeploymentBase do

  context "env_name" do
    it 'doesn\'t match regex' do
      expect{
        described_class.new(name: "spec", env_name: "to_fail", region: "deployment-region", dry_run: false)
      }.to raise_error(/The environment name must consist only of letters, numbers, and hyphens/)
    end
  end

  context "#subdomain_with_trailing_dot" do
    let(:instance) {
      described_class.new(env_name: env_name,
                          region: 'whatever',
                          name: 'a_name',
                          dry_run: false)
    }

    context "production env" do
      let(:env_name) { 'production' }

      context "blank site_name" do
        it 'is blank' do
          expect(instance.send(:subdomain_with_trailing_dot, site_name: "")).to be_blank
        end
      end

      context "non-blank site_name" do
        it 'is the site_name' do
          expect(instance.send(:subdomain_with_trailing_dot, site_name: "hi")).to eq "hi."
        end
      end
    end

    context "non-production env" do
      let(:env_name) { 'qa' }

      context "blank site_name" do
        it 'is the env name' do
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "")).to eq "#{env_name}."
        end
      end

      context "non-blank site_name" do
        it 'is the site_name' do
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "hi")).to eq "hi-#{env_name}."
        end
      end
    end
  end

  context "#secrets" do

    it "can define deployment-wide secrets" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        secrets :common do
          specification do
            content do
              { foo: "blah" }
            end
          end
        end
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)
      secrets = instance.common_secrets

      expect(secrets).to be_a OpenStax::Aws::Secrets
      expect(secrets.key_prefix).to eq "/dev/spec/common"
    end

    it "cannot define two secrets with the same name" do
      expect{
        Class.new(described_class) do
          template_directory __dir__, 'support/templates/factory_test'

          secrets :common
          secrets :common
        end
      }.to raise_error(/secrets once/)
    end

    it "cannot define secrets with the same name as a stack" do
      expect{
        Class.new(described_class) do
          template_directory __dir__, 'support/templates/factory_test'

          stack :common
          secrets :common
        end
      }.to raise_error(/stack with that ID/)
    end

    it "cannot define stack with the same name as a secrets" do
      expect{
        Class.new(described_class) do
          template_directory __dir__, 'support/templates/factory_test'

          secrets :common
          stack :common
        end
      }.to raise_error(/secrets with that ID/)
    end

  end

  context "#deployed_parameters" do
    it "gets the deployed parameters for each stack in the deployment" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        stack :network
        stack :app
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.network_stack).to receive(:deployed_parameters)
      expect(instance.app_stack).to receive(:deployed_parameters)
      # Not really making network calls here, this spec not set up for VCR
      expect(instance.deployed_parameters).to include("dev-spec-network" => nil, "dev-spec-app" => nil)
    end
  end

  context "#stacks" do
    it "makes the stacks available via an array" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        stack :network
        stack :app
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.stacks.map(&:name)).to contain_exactly("dev-spec-network", "dev-spec-app")
    end

    it "works if no stacks defined" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.stacks).to be_empty
    end
  end

  context "#stack" do

    it "sets a lot of default stack options" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        stack :network
        stack :app
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.name).to eq "dev-spec-app"
      expect(instance.app_stack.region).to eq "deployment-region"
      expect(instance.app_stack.template.absolute_file_path).to end_with("support/templates/factory_test/app.yml")
      expect(instance.app_stack.enable_termination_protection).to eq false
      expect(instance.app_stack.parameter_defaults[:env_name]).to eq "dev"
      expect(instance.app_stack.parameter_defaults[:network_stack_name]).to eq "dev-spec-network"
    end

    it "doesn't freak out if it can't find another stack for a _stack_name parameter default" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        # stack :network # commenting out to show that it is missing
        stack :app do
          parameter_defaults do
            env_name "something_else"
          end
        end
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.parameter_defaults).to_not have_key(:network_stack_name)
    end

    it "does not overwrite existing parameter defaults" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        stack :app do
          parameter_defaults do
            env_name "something_else"
          end
        end
      end

      instance = deployment_class.new(name: "spec", env_name: "dev", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.parameter_defaults[:env_name]).to eq "something_else"
    end

    it "turns on termination protection for production envs" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'

        stack :app
      end

      instance = deployment_class.new(name: "spec", env_name: "production", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.enable_termination_protection).to eq true
    end

    it "makes good stack names when env_name not set" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'
        stack :app
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.name).to eq "spec-app"
    end

    it "can have stack name overridden" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'
        stack :app do
          name { "my-#{name}-override-app" }
        end
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region", dry_run: false)

      expect(instance.app_stack.name).to eq "my-spec-override-app"
    end

    it "must be given an id" do
      expect{
        deployment_class = Class.new(described_class) do
          template_directory __dir__, 'support/templates/factory_test'
          stack nil do
          end
        end
      }.to raise_error(StandardError, /first argument/)
    end
  end

  context "#template_directory" do
    it "takes a sequence of directory parts" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/factory_test'
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region")
      expect(instance.template_directory).to end_with("spec/support/templates/factory_test")
    end
  end

  context "tags" do
    it "can set tags at the deployment level with overrides at the stack level" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates'

        tag :howdy, "there"
        tag :foo, "bar"

        stack :simple do
          tag :foo, "bar"
        end
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region")

      expect(instance.simple_stack.tags.map{|tag| {tag.key => tag.value}}).to contain_exactly({"howdy" => "there"}, {"foo" => "bar"})
    end

    it "can set tags with blocks evaluated in the context of the deployment instance" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates'

        tag(:foo) { bar }

        def bar
          "bar"
        end
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region")

      expect(instance.tags).to eq({"foo" => "bar"})
    end

    it "allows tags up the inheritance tree but does not pollute between children" do
      base_class = Class.new(described_class) do
        tag :howdy, "there"
        tag :foo, "bar"

        stack :simple do
          tag :foo, "bar"
        end
      end

      child_class_1 = Class.new(base_class) do
        tag :something_else, "foo"
      end

      child_class_2 = Class.new(base_class)

      expect(child_class_1.tags.keys).to contain_exactly("howdy", "foo", "something_else")
      expect(child_class_2.tags.keys).to contain_exactly("howdy", "foo")

      grandchild_class_1 = Class.new(child_class_1) do
        tag :so_far_down, "foo"
      end

      grandchild_class_2 = Class.new(child_class_2) do
        tag :other, "bar"
      end

      expect(grandchild_class_1.tags.keys).to contain_exactly("howdy", "foo", "something_else", "so_far_down")
      expect(grandchild_class_2.tags.keys).to contain_exactly("howdy", "foo", "other")
    end
  end

  context "deployment parameter defaults" do
    it "allows explicit defauts" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/parameter_defaults'
        stack :app

        def parameter_default(parameter_name)
          "my-bucket-name" if parameter_name == "BucketName"
        end
      end

      instance = deployment_class.new(name: "spec", region: "deployment-region")
      expect(instance.app_stack.parameter_defaults[:bucket_name]).to eq "my-bucket-name"
    end

    it "provides built-in defauts" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/parameter_defaults'
        stack :app
      end

      instance = deployment_class.new(env_name: "howdy", name: "spec", region: "deployment-region")
      expect(instance.app_stack.parameter_defaults[:env_name]).to eq "howdy"
    end

    it "allows built-in defauts to be overridden" do
      deployment_class = Class.new(described_class) do
        template_directory __dir__, 'support/templates/parameter_defaults'
        stack :app

        def built_in_parameter_default(parameter_name)
          "something-else"
        end
      end

      instance = deployment_class.new(env_name: "howdy", name: "spec", region: "deployment-region")
      expect(instance.app_stack.parameter_defaults[:env_name]).to eq "something-else"
    end
  end

  context "#sam_build_directory" do
    it "can be set" do
      deployment_class = Class.new(described_class) do
        sam_build_directory '/Foo/bar', '../howdy'
      end
      instance = deployment_class.new(env_name: "howdy", name: "spec", region: "some-region")
      expect(instance.sam_build_directory).to eq "/Foo/howdy"
    end
  end

end
