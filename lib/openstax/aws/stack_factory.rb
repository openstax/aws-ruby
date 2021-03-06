module OpenStax::Aws
  class StackFactory
    attr_reader :attributes, :id

    def initialize(id:, deployment:)
      raise "`deployment` cannot be nil" if deployment.nil?

      @id = id
      @deployment = deployment
      @attributes = {
        parameter_defaults: {},
        tags: {}
      }
    end

    def self.build(id:, deployment:, &block)
      factory = new(id: id, deployment: deployment)
      factory.instance_eval(&block) if block_given?
      factory.build
    end

    def method_missing(name, *args, &block)
      if args.empty? && !block_given?
        attributes[name.to_sym]
      else
        attributes[name.to_sym] = args.empty? ?
                                    @deployment.instance_eval(&block) :
                                    args[0]
      end
    end

    def template_directory(*directory_parts)
      if directory_parts.empty? && !block_given?
        attributes[:template_directory]
      else
        directory_parts = yield if directory_parts.empty?
        attributes[:template_directory] = File.join(*directory_parts)
      end
    end

    def autoset_absolute_template_path(fallback_base_directory)
      base_directory = template_directory || fallback_base_directory

      if base_directory.blank?
        raise "Tried to autoset the absolute_template_path but didn't have " \
              "access to a base directory (e.g. set with template_directory)"
      end

      if relative_template_path
        path = File.join(base_directory, relative_template_path)
      else
        path = File.join(base_directory, "#{@id}.yml")

        if !File.file?(path)
          path = File.join(base_directory, "#{@id}.yml.erb")

          if !File.file?(path)
            path = File.join(base_directory, "#{@id}.json")
            if !File.file?(path)
              raise "Couldn't infer an existing template file for stack #{@id}"
            end
          end
        end
      end

      self.absolute_template_path(path)
    end

    def parameter_defaults(&block)
      factory = ParameterDefaultsFactory.new(@deployment)
      factory.instance_eval(&block) if block_given?
      attributes[:parameter_defaults].merge!(factory.attributes)
    end

    def volatile_parameters(&block)
      attributes[:volatile_parameters_block] = block
    end

    def secrets(&block)
      attributes[:secrets_blocks] ||= []
      attributes[:secrets_blocks].push(block)
    end

    def cycle_if_different_parameter(name=nil, &block)
      attributes[:cycle_if_different_parameter] = block.present? ? block.call : name
    end

    def tag(key, value)
      raise 'The first argument to `tag` must not be blank' if key.blank?
      (attributes[:tags] ||= {})[key] = value
    end

    def build
      autoset_absolute_template_path(nil) if absolute_template_path.blank?

      initializer_args = {
        id: id,
        name: attributes[:name],
        tags: @deployment.tags.merge(attributes[:tags]),
        region: attributes[:region],
        enable_termination_protection: attributes[:enable_termination_protection],
        absolute_template_path: attributes[:absolute_template_path],
        capabilities: attributes[:capabilities],
        parameter_defaults: attributes[:parameter_defaults],
        volatile_parameters_block: attributes[:volatile_parameters_block],
        secrets_blocks: attributes[:secrets_blocks],
        secrets_context: @deployment,
        secrets_namespace: [@deployment.env_name, @deployment.name],
        shared_secrets_substitutions_block: @deployment.shared_secrets_substitutions_block,
        cycle_if_different_parameter: attributes[:cycle_if_different_parameter],
        dry_run: attributes[:dry_run]
      }

      template = Template.from_absolute_file_path(absolute_template_path)
      if template.is_sam?
        if !@deployment.respond_to?(:sam_build_directory)
          raise "You must set the SAM build directory with a call to `sam_build_directory`"
        end

        initializer_args[:build_directory] = @deployment.sam_build_directory
        SamStack.new(**initializer_args)
      else
        Stack.new(**initializer_args)
      end
    end

    class ParameterDefaultsFactory
      attr_reader :attributes

      def initialize(context)
        @context = context
        @attributes = {}
      end

      def method_missing(name, *args, &block)
        attributes[name.to_sym] = args[0] || @context.instance_eval(&block)
      end
    end

    class VolatileParametersFactory
      attr_reader :attributes

      def initialize(context)
        raise "context cannot be nil" if context.nil?
        @context = context
        @attributes = {}
      end

      def method_missing(name, *args, &block)
        raise "Volatile parameter `#{name}` cannot be called with arguments, only a block" if !args.empty?
        raise "Volatile parameter `#{name}` must be called with a block to set the parameter value" if !block_given?
        attributes[name.to_sym] = @context.instance_eval(&block)
      end
    end

  end
end
