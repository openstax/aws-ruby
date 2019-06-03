module SecretsDslSpec
  class Deployment < OpenStax::Aws::DeploymentBase

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
        substitutions do
          domain { domain_value }
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
      "y'all"
    end

    def create(some_sha:, bucket_name:)
      main_stack.create(params: {some_sha: some_sha, bucket_name: bucket_name}, wait: true)
    end

    def delete
      main_stack.delete(wait: true)
    end

    def initialize(env_name:, region:, dry_run: true)
      super(env_name: env_name, region: region, name: "secrets-dsl-spec", dry_run: dry_run)
    end

  end
end
