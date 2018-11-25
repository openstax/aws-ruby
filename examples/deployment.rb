require 'byebug'

module OpenStax::Aws::SomeApp
  class Deployment < OpenStax::Aws::DeploymentBase

    def initialize(env_name:, region:)
      super(env_name: env_name, region: region, name: "some_name")
    end

    def create(app_image_id:, sha: nil)
      create_network_stack
      create_redis_stack
      create_parameters(deployed_app_sha: sha || image_sha(app_image_id))
      create_app_stack(app_image_id: app_image_id)
    end

    def create_network_stack(wait: true)
      upload_template(absolute_file_path: File.join(File.dirname(__FILE__), "network.yml"))

      client.create_stack(
        stack_name: network_stack_name,
        template_url: template_url(file_name: "network.yml")
      )

      wait_for_stack_creation(stack_name: network_stack_name) if wait
    end

    def create_redis_stack(wait: true)
      upload_template(absolute_file_path: File.join(File.dirname(__FILE__), "redis.yml"))

      client.create_stack(
        stack_name: redis_stack_name,
        template_url: template_url(file_name: "redis.yml"),
        parameters: client_params(
          network_stack_name: network_stack_name
        )
      )

      wait_for_stack_creation(stack_name: redis_stack_name) if wait
    end

    def create_parameters(deployed_app_sha:)
      redis_host = stack_output_value(stack: redis_stack, key: "ElastiCacheAddress")

      parameters.create(
        specification: OpenStax::Aws::ParametersSpecification.from_git(
          org_slash_repo: "openstax/some_app_repo",
          sha: deployed_app_sha,
          path: 'config/secrets.yml.example',
          format: :yml,
          top_key: :production
        ),
        substitutions: {
          domain: domain,
          env_name: env_name,
          redis_url: "redis://#{redis_host}:6379/0"
        }
      )
    end

    def create_app_stack(app_image_id:)
      upload_template(absolute_file_path: File.join(File.dirname(__FILE__), "app.yml"))

      client.create_stack(
        stack_name: app_stack_name,
        template_url: template_url(file_name: "app.yml"),
        capabilities: ["CAPABILITY_IAM"],
        parameters: client_params(
          network_stack_name: network_stack_name,
          env_name: env_name,
          branch_name_or_sha: "",
          hosted_zone_name: "something.domain.com",
          domain: domain,
          web_server_image_id: app_image_id,
          web_server_desired_capacity: '1',
          parameter_namespace: parameter_namespace,
          key_name: "some-aws-keypair-name"
        )
      )
    end

    def delete
      delete_stack(stack_name: app_stack_name)
      delete_stack(stack_name: redis_stack_name)

      wait_for_stack_deletion(stack_name: app_stack_name)
      wait_for_stack_deletion(stack_name: redis_stack_name)

      parameters.delete

      delete_stack(stack_name: network_stack_name)
    end

    def update_app_image(new_app_image_id:, dry_run: true)
      apply_change_set(dry_run: dry_run, params: {
        stack_name: app_stack_name,
        template_url: template_url(file_name: "app.yml"),
        capabilities: ["CAPABILITY_IAM"],
        parameters: client_params(
          network_stack_name: network_stack_name,
          env_name: env_name,
          branch_name_or_sha: "",
          hosted_zone_name: "something.domain.com",
          domain: domain,
          web_server_image_id: new_app_image_id,
          web_server_desired_capacity: asg.desired_capacity.to_s,
          parameter_namespace: parameter_namespace,
          key_name: "some-aws-keypair-name"
        ),
        change_set_name: "update-app-image-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}-#{new_app_image_id}"
      })
    end

    protected

    def parameter_namespace
      'some_name'
    end

    def domain
      build_domain(site_name: "some_name")
    end

    def network_stack_name
      "some_name-#{env_name}-network"
    end

    def redis_stack_name
      "some_name-#{env_name}-redis"
    end

    def app_stack_name
      "some_name-#{env_name}-app"
    end

    def asg_name
      "some_name-#{env_name}-app-web-asg"
    end

    def asg
      auto_scaling_group(name: asg_name)
    end

    def redis_stack
      @redis_stack ||= Aws::CloudFormation::Stack.new(redis_stack_name, client, region: region)
    end

  end
end
