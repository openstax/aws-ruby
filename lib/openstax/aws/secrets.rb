module OpenStax::Aws
  class Secrets

    # We store "secrets" in the AWS Parameter store.  Secrets can be truly secret
    # values (e.g. keys) or just some configuration values.

    attr_reader :region, :env_name, :dry_run, :namespace

    # TODO remove use of env_name, just make people provide namespace

    def initialize(region:, env_name: nil, dry_run: true, namespace:)
      @region = region
      @env_name = env_name
      @dry_run = dry_run
      @namespace = namespace
      @client = Aws::SSM::Client.new(region: region)
      @substitutions = {}
    end

    def define(specifications:, substitutions: {})
      @specifications = specifications
      @substitutions = substitutions
    end

    def create(specifications: nil, substitutions: nil)
      # Build all secrets first so we hit any errors before we send any to AWS
      built_secrets = build_secrets(specifications: specifications, substitutions: substitutions)

      OpenStax::Aws.logger.info("**** DRY RUN ****") if dry_run

      OpenStax::Aws.logger.info("Creating the following secrets in the AWS parameter store: #{built_secrets}")

      # Ship 'em
      if !dry_run
        built_secrets.each do |built_secret|
          client.put_parameter(built_secret)
        end
      end
    end

    def update(specifications: nil, substitutions: nil)
      # Temporary approach until we do something smarter
      delete
      create(specifications: specifications, substitutions: substitutions)
    end

    def build_secrets(specifications:, substitutions:)
      specifications ||= @specifications
      substitutions ||= @substitutions

      specifications = [specifications].flatten

      raise "Cannot build secrets without a specification" if specifications.empty?

      expanded_data = {}

      # later specifications override earlier ones
      specifications.reverse.each do |specification|
        expanded_data.merge!(specification.expanded_data)
      end

      expanded_data.map do |secret_name, spec_value|
        value = case spec_value.strip
        when /^random\(hex,(\d+)\)$/
          num_characters = $1.to_i
          SecureRandom.hex(num_characters)[0..num_characters-1]
        when "uuid"
          SecureRandom.uuid
        when /{([^{}]+)}/
          spec_value.gsub(/({{\W*(\w+)\W*}})/) do |match|
            if (!substitutions.has_key?($2) && !substitutions.has_key?($2.to_sym))
              raise "no substitution provided for #{$2}"
            end

            substitutions[$2] || substitutions[$2.to_sym]
          end
        when /^ssm\((.*)\)$/
          begin
            client.get_parameter({
              name: substitutions[$1] || substitutions[$1.to_sym],
              with_decryption: true
            }).parameter.value
          rescue Aws::SSM::Errors::ParameterNotFound => ee
            raise "Could not get secret '#{$1}'"
          end
        else # use literal value
          spec_value
        end

        {
          name: "#{key_prefix}/#{secret_name}",
          type: "String",
          value: value
        }
      end
    end

    def data
      @data ||= data!
    end

    def data!
      {}.tap do |hash|
        client.get_parameters_by_path({
          path: key_prefix,
          recursive: true,
          with_decryption: true
        }).each do |response|
          response.parameters.each do |parameter|
            hash[parameter.name] = {
              type: parameter.type,
              value: parameter.value
            }
          end
        end
      end
    end

    def get(local_name)
      local_name = "/#{local_name}" unless local_name.chr == "/"
      data["#{key_prefix}#{local_name}"].try(:[], :value)
    end

    def delete
      secret_names = data!.keys
      return if secret_names.empty?

      OpenStax::Aws.logger.info("**** DRY RUN ****") if dry_run

      OpenStax::Aws.logger.info("Deleting the following secrets in the AWS parameter store: #{secret_names}")

      if !dry_run
        @data = nil # remove cached values as they are about to get cleared remotely

        # Can send max 10 secret names at a time
        secret_names.each_slice(10) do |some_secret_names|
          response = client.delete_parameters({names: some_secret_names})

          if response.invalid_parameters.any?
            OpenStax::Aws.logger.debug("Unable to delete some secrets (likely already deleted): #{response.invalid_parameters}")
          end
        end
      end
    end

    def key_prefix
      "/" + [env_name, namespace].flatten.reject(&:blank?).join("/")
    end

    protected

    attr_reader :client

  end
end
