require 'byebug'

module OpenStax::Aws::SomeApp
  class Deployment < OpenStax::Aws::DeploymentBase

    stack :network
    stack :redis
    stack :app do
      parameter_defaults do
        web_server_desired_capacity '1'
        secrets_namespace { secrets_namespace }
      end
      volatile_parameters do
        web_server_desired_capacity { resource("Asg").desired_capacity }
      end
    end

    def initialize(env_name:, region:, dry_run: true)
      super(env_name: env_name, region: region, name: "some_name", dry_run: dry_run)
    end

    def create(app_image_id:, sha: nil)
      network_stack.create
      redis_stack.create

      network_stack.wait_for_stack_creation
      redis_stack.wait_for_stack_creation

      create_parameters(deployed_app_sha: sha || image_sha(app_image_id))

      app_stack.create(params: {
        branch_name_or_sha: sha || "",
        web_server_image_id: app_image_id,
      })
    end

    def create_parameters(deployed_app_sha:)
      redis_host = redis_stack.output_value(key: "ElastiCacheAddress")

      parameters.create(
        specification: OpenStax::Aws::ParametersSpecification.from_git(
          org_slash_repo: "openstax/some_app_repo",
          sha: deployed_app_sha,
          path: 'config/secrets.yml.example',
          format: :yml,
          top_key: :production
        ),
        substitutions: {
          env_name: env_name,
          redis_url: "redis://#{redis_host}:6379/0"
        }
      )
    end

    def delete
      app_stack.delete
      redis_stack.delete

      app_stack.wait_for_stack_deletion
      redis_stack.wait_for_stack_deletion

      parameters.delete

      network_stack.delete
    end

    def update_app_image(new_app_image_id:, dry_run: true)
      app_stack.apply_change_set(params: {
        web_server_image_id: new_app_image_id
      })
    end

    protected

    # A good way to handle deployment-wide stack parameter defaults
    def parameter_default(parameter_name)
      case parameter_name
      when "HostedZoneName"
        "something.domain.com"
      when "KeyName"
        "my-key-pair-on-aws"
      end
    end

    def secrets_namespace
      'some_name'
    end

  end
end
