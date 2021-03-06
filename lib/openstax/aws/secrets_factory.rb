module OpenStax::Aws
  class SecretsFactory
    def initialize(region:, context:, namespace:, dry_run: true,
                   for_create_or_update:, shared_substitutions_block: nil)
      raise ArgumentError, "context cannot be nil" if context.nil?
      @context = context
      @specification_blocks = []
      @substitutions_block = nil
      @region = region
      @top_namespace = namespace
      @next_namespace = nil
      @dry_run = dry_run
      @for_create_or_update = for_create_or_update
      @shared_substitutions_block = shared_substitutions_block
    end

    def namespace(*args, &block)
      @next_namespace = args.any? ? args[0] : @context.instance_eval(&block)
    end

    def specification(&block)
      @specification_blocks.push(block)
    end

    def substitutions(&block)
      @substitutions_block = block
    end

    def specification_instances
      raise "Must define secrets specification" if @specification_blocks.empty?

      @specification_blocks.map do |specification_block|
        factory = SecretsSpecificationFactory.new(@context)
        factory.instance_eval &specification_block
        attributes = factory.attributes

        if attributes.has_key?(:org_slash_repo)
          OpenStax::Aws::SecretsSpecification.from_git(
            org_slash_repo: attributes[:org_slash_repo],
            sha: attributes[:sha],
            path: attributes[:path],
            github_token: attributes[:github_token],
            format: attributes[:format].to_sym,
            top_key: attributes[:top_key].to_sym,
            preparser: attributes[:preparser]
          )
        elsif attributes.has_key?(:content)
          OpenStax::Aws::SecretsSpecification.from_content(
            content: attributes[:content],
            format: attributes[:format],
            top_key: attributes[:top_key],
            preparser: attributes[:preparser]
          )
        else
          raise "Cannot build a secrets specification"
        end
      end
    end

    def substitutions_hash
      shared_substitutions = substitutions_hash_from_block(@shared_substitutions_block)
      local_substitutions = substitutions_hash_from_block(@substitutions_block)

      shared_substitutions.merge(local_substitutions)
    end

    def substitutions_hash_from_block(block)
      return {} if block.nil?

      factory = SecretsSubstitutionsFactory.new(@context)
      factory.instance_eval &block
      factory.attributes
    end

    def full_namespace
      [@top_namespace, @next_namespace].flatten.reject(&:blank?)
    end

    def instance
      Secrets.new(region: @region, namespace: full_namespace, dry_run: @dry_run).tap do |secrets|
        if @for_create_or_update
          secrets.define(specifications: specification_instances, substitutions: substitutions_hash)
        end
      end
    end
  end

  class SecretsSpecificationFactory
    attr_reader :attributes

    def initialize(context)
      raise ArgumentError, "context cannot be nil" if context.nil?
      @context = context
      @attributes = {}
    end

    def format(&block)
      store_attribute(:format, &block)
    end

    def method_missing(name, *args, &block)
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
      raise ArgumentError, "context cannot be nil" if context.nil?
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
