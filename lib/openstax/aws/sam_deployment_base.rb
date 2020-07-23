module OpenStax::Aws
  class SamDeploymentBase < DeploymentBase

    def initialize(env_name:, region:, name:, dry_run: true)
      super(env_name: env_name, region: region, name: name, dry_run: dry_run)
    end

    class << self
      def serverless_stack(id, &block)
        if method_defined?("serverless_stack")
          raise "Cannot define `#{id}` as the serverless stack because there is already a serverless stack"
        end

        stack(id, &block)

        define_method("serverless_stack") do
          send("#{id}_stack")
        end
      end
    end

  end
end
