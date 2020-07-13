module OpenStax::Aws
  class Tag

    attr_reader :key, :value

    AWS_TAG_KEY_REGEX =   /\A[\w\-\/.+=:@]{1,128}\z/
    AWS_TAG_VALUE_REGEX = /\A[\w\-\/.+=:@ ]{0,256}\z/

    def initialize(key, value)
      if key.nil? || !key.match(AWS_TAG_KEY_REGEX)
        raise "The tag key '#{key}' is invalid: must be a non-blank ID matching #{AWS_TAG_KEY_REGEX}"
      end

      @key = key.to_s

      if @key.starts_with?("aws:")
        raise "The tag key '#{@key}' is invalid: it cannot start with 'aws:'"
      end

      if value.nil?
        raise "The tag value for key '#{key}' cannot be nil"
      end

      if !value.match(AWS_TAG_VALUE_REGEX)
        raise "The tag value '#{value}' must be a tag value matching #{AWS_TAG_VALUE_REGEX}"
      end

      @value = value.to_s
    end
  end
end
