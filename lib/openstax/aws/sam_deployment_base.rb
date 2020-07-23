module OpenStax::Aws
  class SamDeploymentBase < DeploymentBase

    def initialize(env_name:, region:, name:, app:, dry_run: true)
      @app = app
      super(env_name: env_name, region: region, name: name, dry_run: dry_run)
    end

    def deploy(params: {}, wait: true)
      command = "sam deploy" \
                " --template-file #{app.packaged_template_file}" \
                " --capabilities CAPABILITY_IAM" \
                " --s3-bucket #{bucket}" \
                " --s3-prefix #{stack_name}" \
                " --parameter-overrides #{self.class.format_hash_as_cli_stack_parameters(params)}" \
                " --stack-name #{stack_name}"

      if !tags.empty?
        command += " --tags #{self.class.format_hash_as_cli_tags(tags)}"
      end

      System.call(command, logger: logger, dry_run: dry_run)
    end

    def bucket
      Template.from_absolute_file_path(app.packaged_template_file)
              .serverless_function_bucket
    end

    def stack_name
      [env_name,name].compact.join("-").gsub("_","-"))
    end

    def self.format_hash_as_cli_stack_parameters(params={})
      params.map{|key, value| "ParameterKey=#{key},ParameterValue=#{value}"}.join(" ")
    end

    def self.format_hash_as_cli_tags(params={})
      params.map{|key, value| "Key=#{key},Value=#{value}"}.join(" ")
    end

  end
end
