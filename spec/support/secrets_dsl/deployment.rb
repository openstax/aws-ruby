module SecretsDslSpec
  class Deployment < OpenStax::Aws::DeploymentBase

    attr_accessor :value_to_change_before_update

    template_directory __dir__, "."

    stack :main do
      secrets do |parameters|
        specification do
          org_slash_repo { "openstax/aws-ruby" }
          sha { parameters[:some_sha] }
          path { 'spec/support/secrets_dsl/secrets.yml' }
          format { 'yml' }
          top_key { 'production' }
        end
        specification do
          content do
            { content_key: "{{ domain }}" }
          end
        end
        substitutions do
          domain { domain_value }
        end
      end
      secrets do
        specification do
          content do
            { more_secrets: "foo" }
          end
        end
      end
    end

    secrets_substitutions do
      shared_value { shared_value }
    end

    def domain_value
      "something-deployment-specific"
    end

    def shared_value
      value_to_change_before_update
    end

    def create(some_sha:, bucket_name:)
      main_stack.create(params: {some_sha: some_sha, bucket_name: bucket_name}, wait: true)
    end

    def update
      main_stack.apply_change_set(wait: true)
    end

    def delete
      main_stack.delete(wait: true)
    end

    def initialize(env_name:, region:, dry_run: true)
      super(env_name: env_name, region: region, name: "secrets-dsl-spec", dry_run: dry_run)
      @value_to_change_before_update = "y'all"
    end

  end
end
