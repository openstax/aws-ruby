module OpenStax::Aws
  class StackFactory
    attr_reader :attributes

    def initialize(id:, deployment:)
      raise "`deployment` cannot be nil" if deployment.nil?

      @id = id
      @deployment = deployment
      @attributes = {
        parameter_defaults: {}
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
          path = File.join(base_directory, "#{@id}.json")
          if !File.file?(path)
            raise "Couldn't infer an existing template file for stack #{@id}"
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
      attributes[:secrets_block] = block
    end

    def build
      autoset_absolute_template_path(nil) if absolute_template_path.blank?

      Stack.new(
        id: id,
        name: attributes[:name],
        region: attributes[:region],
        enable_termination_protection: attributes[:enable_termination_protection],
        absolute_template_path: attributes[:absolute_template_path],
        capabilities: attributes[:capabilities],
        parameter_defaults: attributes[:parameter_defaults],
        volatile_parameters_block: attributes[:volatile_parameters_block],
        secrets_block: attributes[:secrets_block],
        secrets_context: @deployment,
        secrets_namespace: @deployment.env_name,
        dry_run: attributes[:dry_run]
      )
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

    class SecretsFactory
      def initialize(region:, context:, namespace:, dry_run: true, for_create_or_update:)
        raise "context cannot be nil" if context.nil?
        @context = context
        @specification_block = nil
        @substitutions_block = nil
        @region = region
        @top_namespace = namespace
        @next_namespace = nil
        @dry_run = dry_run
        @for_create_or_update = for_create_or_update
      end

      def namespace(&block)
        @next_namespace = @context.instance_eval(&block)
      end

      def specification(&block)
        @specification_block = block
      end

      def substitutions(&block)
        @substitutions_block = block
      end

      def specification_instance
        raise "Must define secrets specification" if @specification_block.nil?

        factory = SecretsSpecificationFactory.new(@context)
        factory.instance_eval &@specification_block
        attributes = factory.attributes

        if attributes.has_key?(:org_slash_repo)
          OpenStax::Aws::SecretsSpecification.from_git(
            org_slash_repo: attributes[:org_slash_repo],
            sha: attributes[:sha],
            path: attributes[:path],
            format: attributes[:format].to_sym,
            top_key: attributes[:top_key].to_sym
          )
        elsif attributes.has_key?(:content)
          raise "Nyi"
        else
          raise "Cannot build a secrets specification"
        end
      end

      def substitutions_hash
        return {} if @substitutions_block.nil?

        factory = SecretsSubstitutionsFactory.new(@context)
        factory.instance_eval &@substitutions_block
        factory.attributes
      end

      def full_namespace
        [@top_namespace, @next_namespace].flatten.reject(&:blank?)
      end

      def instance
        Secrets.new(region: @region, namespace: full_namespace, dry_run: @dry_run).tap do |secrets|
          if @for_create_or_update
            secrets.define(specification: specification_instance, substitutions: substitutions_hash)
          end
        end
      end
    end

    class SecretsSpecificationFactory
      attr_reader :attributes

      def initialize(context)
        raise "context cannot be nil" if context.nil?
        @context = context
        @attributes = {}
      end

      def format(&block)
        store_attribute(:format, &block)
        # attributes[name.to_sym] = @context.instance_eval(&block)
      end

      def method_missing(name, *args, &block)
        # raise "Secrets specification option `#{name}` cannot be called with arguments, only a block" if !args.empty?
        # raise "Secrets specification option `#{name}` must be called with a block to set the value" if !block_given?
        # attributes[name.to_sym] = @context.instance_eval(&block)
        store_attribute(name, *args, &block)
      end

      def store_attribute(name, *args, &block)
        raise "Secrets specification option `#{name}` cannot be called with arguments, only a block" if !args.empty?
        raise "Secrets specification option `#{name}` must be called with a block to set the value" if !block_given?
        attributes[name.to_sym] = @context.instance_eval(&block)
      end
    end

    class SecretsSubstitutionsFactory
      attr_reader :attributes

      def initialize(context)
        raise "context cannot be nil" if context.nil?
        @context = context
        @attributes = {}
      end

      def method_missing(name, *args, &block)
        raise "Secrets substitition `#{name}` cannot be called with arguments, only a block" if !args.empty?
        raise "Secrets substitution `#{name}` must be called with a block to set the substitution value" if !block_given?
        attributes[name.to_sym] = @context.instance_eval(&block)
      end
    end

  end
end
