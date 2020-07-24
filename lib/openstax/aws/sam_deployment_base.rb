module OpenStax::Aws
  class SamDeploymentBase < DeploymentBase

    def initialize(env_name:, region:, name:, app:, dry_run: true)
      @app = app
      super(env_name: env_name, region: region, name: name, dry_run: dry_run)
    end

    def deploy(params: {})
      params = parameter_defaults_from_template(template).merge(params)

      command = "sam deploy" \
                " --template-file #{app.packaged_template_file}" \
                " --capabilities CAPABILITY_IAM" \
                " --s3-bucket #{bucket}" \
                " --s3-prefix #{stack_name}" \
                " --stack-name #{stack_name}"

      if params.any?
        command += " --parameter-overrides #{self.class.format_hash_as_cli_stack_parameters(params)}"
      end

      if tags.any?
        command += " --tags #{self.class.format_hash_as_cli_tags(tags)}"
      end

      System.call(command, logger: logger, dry_run: dry_run)
    end

    def delete(retain_resources: [])
      # There's only one stack in these deployments, make it on the fly here to
      # reuse its delete functionality
      OpenStax::Aws.configuration.without_required_stack_tags do
        OpenStax::Aws::Stack.new(
          name: stack_name, region: region, dry_run: dry_run
        ).delete(retain_resources: retain_resources, wait: true)
      end
    end

    def bucket
      template.serverless_function_bucket
    end

    def template
      Template.from_absolute_file_path(app.packaged_template_file)
    end

    def stack_name
      [env_name,name].compact.join("-").gsub("_","-")
    end

    def self.format_hash_as_cli_stack_parameters(params={})
      params.map{|key, value| "ParameterKey=#{key.to_s.camelcase},ParameterValue=#{value}"}
            .map{|item| "'" + item + "'"}
            .join(" ")
    end

    def self.format_hash_as_cli_tags(params={})
      params.map{|key, value| "#{key}=#{value}"}
            .map{|item| "'" + item + "'"}
            .join(" ")
    end

    protected

    attr_reader :app

  end
end
