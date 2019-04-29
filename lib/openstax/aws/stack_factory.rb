module OpenStax::Aws
  class StackFactory
    attr_reader :attributes

    def initialize(id:, parameter_context:)
      @id = id
      @parameter_context = parameter_context
      @attributes = {
        parameter_defaults: {}
      }
    end

    def self.build(id:, parameter_context:, &block)
      factory = new(id: id, parameter_context: parameter_context)
      factory.instance_eval(&block) if block_given?
      factory.build
    end

    def method_missing(name, *args, &block)
      if args.empty? && !block_given?
        attributes[name.to_sym]
      else
        attributes[name.to_sym] = args.empty? ? yield : args[0] # TODO should this be in the deployment context too?
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
      factory = ParameterDefaultsFactory.new(@parameter_context)
      factory.instance_eval(&block) if block_given?
      attributes[:parameter_defaults].merge!(factory.attributes)
    end

    def build
      Stack.new(
        name: attributes[:name],
        region: attributes[:region],
        enable_termination_protection: attributes[:enable_termination_protection],
        absolute_template_path: attributes[:absolute_template_path],
        capabilities: attributes[:capabilities],
        parameter_defaults: attributes[:parameter_defaults],
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

  end
end
