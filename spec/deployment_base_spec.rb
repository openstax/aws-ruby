require 'spec_helper'

RSpec.describe OpenStax::Aws::DeploymentBase do

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
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "hi")).to eq "hi."
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
      expect(instance.app_stack.parameter_defaults[:key_name]).to eq "dummy-kp"
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

end
