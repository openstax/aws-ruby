module OpenStax::Aws
  class SecretsSet

    def initialize(secrets_array)
      @secrets_array = [secrets_array].flatten
    end

    def create
      @secrets_array.each(&:create)
    end

    def update
      delete
      create
    end

    def delete
      @secrets_array.each(&:delete)
    end

  end
end
