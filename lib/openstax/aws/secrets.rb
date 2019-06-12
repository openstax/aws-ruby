module OpenStax::Aws
  class Secrets

    # We store "secrets" in the AWS Parameter store.  Secrets can be truly secret
    # values (e.g. keys) or just some configuration values.

    attr_reader :region, :dry_run, :namespace

    def initialize(region:, dry_run: true, namespace:)
      @region = region
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
          client.put_parameter(built_secret.merge(overwrite: true))
        end
      end
    end

    def update(specifications: nil, substitutions: nil)
      existing_secrets = data!

      built_secrets = build_secrets(specifications: specifications, substitutions: substitutions)

      changed_secrets = built_secrets.each_with_object([]) do |built_secret, array|

        existing_secret = existing_secrets[built_secret[:name]]

        if existing_secret
          # No need to update if the value is the same
          next if existing_secret[:value] == built_secret[:value]

          # Don't update if different values but generated from same specification
          next if built_secret[:description].try(:starts_with?, "Generated with") &&
                  built_secret[:description] == existing_secret[:description]
        end

        array.push(built_secret)
      end

      OpenStax::Aws.logger.info("**** DRY RUN ****") if dry_run

      if changed_secrets.empty?
        OpenStax::Aws.logger.info("Secrets did not change")
        false
      else
        OpenStax::Aws.logger.info("Updating the following secrets in the AWS parameter store: #{changed_secrets}")

        # Ship 'em
        if !dry_run
          changed_secrets.each do |changed_secret|
            client.put_parameter(changed_secret.merge(overwrite: true))
          end
        end

        true
      end
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
        generated = false
        spec_value = spec_value.strip

        value = case spec_value
        when /^random\(hex,(\d+)\)$/
          generated = true
          num_characters = $1.to_i
          SecureRandom.hex(num_characters)[0..num_characters-1]
        when "uuid"
          generated = true
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
        }.tap do |secret|
          if generated
            secret[:description] = "Generated with #{spec_value}"
          end
        end
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
            hash[parameter.name] = RetrievedParameter.new(parameter, client)
          end
        end
      end
    end

    class RetrievedParameter
      # Helper object to hide the fact that tags and descriptions have to be accessed
      # through separate API calls

      def initialize(parameter, client)
        @raw_parameter = parameter
        @client = client
      end

      def [](key)
        case key
        when :type
          @raw_parameter.type
        when :value
          @raw_parameter.value
        when :tags
          raise "Not yet tested!"
          @tags ||= begin
            (@client.list_tags_for_resource({
              resource_type: "Parameter",
              resource_id: @raw_parameter.arn
            }).tag_list || []).map do |tag| {
              key: tag.key,
              value: tag.value
            } end
          end
        when :description
          @description ||= begin
            @client.describe_parameters({
              parameter_filters: [{
                key: "Name",
                option: "Equals",
                values: [@raw_parameter.name]
              }],
              max_results: 1
            }).parameters[0].description
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
      "/" + [namespace].flatten.reject(&:blank?).join("/")
    end

    protected

    attr_reader :client

  end
end
