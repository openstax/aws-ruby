module OpenStax::Aws
  class StackParameters

    def initialize(stack:, params:, recover_previous_values: true)
      @stack = stack
      @raw_params = params
      @recover_previous_values = recover_previous_values
    end

    def [](key)
      if @recover_previous_values && @raw_params[key] == :use_previous_value
        @stack.deployed_parameters[key]
      else
        @raw_params[key]
      end
    end

  end
end
