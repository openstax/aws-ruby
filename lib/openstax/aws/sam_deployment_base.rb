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

      if is_production?
        client.update_termination_protection({
          enable_termination_protection: true,
          stack_name: stack_name
        })
      end
    end

    def delete(retain_resources: [])
      sam_stack.delete(retain_resources: retain_resources, wait: true)
    end

    def bucket
      template.serverless_function_bucket
    end

    def template
      Template.from_absolute_file_path(app.packaged_template_file)
    end

    def sam_stack
      # There's only one stack in these deployments, make it on the fly here
      OpenStax::Aws::Stack.new(
        name: stack_name, region: region, dry_run: dry_run, tags: tags
      )
    end

    def failed?(reload: false)
      sam_stack.status(reload: reload).failed?
    end

    def succeeded?(reload: false)
      sam_stack.status(reload: reload).succeeded?
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
