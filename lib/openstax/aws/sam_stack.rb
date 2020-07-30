module OpenStax::Aws
  class SamStack < Stack

    attr_reader :build_directory

    def initialize(id: nil, name:, tags: {},
                   region:, enable_termination_protection: false,
                   absolute_template_path: nil,
                   capabilities: nil, parameter_defaults: {},
                   volatile_parameters_block: nil,
                   secrets_blocks: [], secrets_context: nil, secrets_namespace: nil,
                   shared_secrets_substitutions_block: nil,
                   cycle_if_different_parameter: nil,
                   build_directory:,
                   dry_run: true)
      @build_directory = build_directory

      super(id: id,
            name: name,
            tags: tags,
            region: region,
            enable_termination_protection: enable_termination_protection,
            absolute_template_path: absolute_template_path,
            capabilities: capabilities,
            parameter_defaults: parameter_defaults,
            volatile_parameters_block: volatile_parameters_block,
            secrets_blocks: secrets_blocks,
            secrets_context: secrets_context,
            secrets_namespace: secrets_namespace,
            shared_secrets_substitutions_block: shared_secrets_substitutions_block,
            cycle_if_different_parameter: cycle_if_different_parameter,
            dry_run: dry_run)
    end

    def build
      # SAM doesn't have an API or SDK - we have to make calls to its CLI
      command = "sam build -t #{absolute_template_path} -b #{build_directory}"
      System.call(command, logger: logger, dry_run: dry_run)
    end

    def deploy(bucket_name:, params: {})
      # SAM doesn't have an API or SDK - we have to make calls to its CLI
      params = parameter_defaults.merge(params)

      command = "sam deploy" \
                " --template-file #{build_directory}/template.yaml" \
                " --capabilities CAPABILITY_IAM" \
                " --s3-bucket #{bucket_name}" \
                " --s3-prefix #{name}" \
                " --stack-name #{name}"

      if params.any?
        command += " --parameter-overrides #{self.class.format_hash_as_cli_stack_parameters(params)}"
      end

      if tags.any?
        command += " --tags #{self.class.format_tags_as_cli_tags(tags)}"
      end

      System.call(command, logger: logger, dry_run: dry_run)

      if enable_termination_protection
        client.update_termination_protection({
          enable_termination_protection: true,
          stack_name: stack_name
        })
      end
    end

    def self.format_hash_as_cli_stack_parameters(params={})
      params.map{|key, value| "ParameterKey=#{key.to_s.camelcase},ParameterValue=#{value}"}
            .map{|item| "'" + item + "'"}
            .join(" ")
    end

    def self.format_tags_as_cli_tags(tags=[])
      tags.map{|tag| "'#{tag.key}=#{tag.value}'"}
          .join(" ")
    end

  end
end
