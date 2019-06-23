module OpenStax::Aws
  class S3TextFile

    attr_reader :bucket_name, :bucket_region, :key

    def initialize(bucket_name:, bucket_region:, key:)
      raise ArgumentError, "bucket_name cannot be nil" if bucket_name.nil?
      raise ArgumentError, "bucket_region cannot be nil" if bucket_region.nil?
      raise ArgumentError, "key cannot be nil" if key.nil?

      @bucket_name = bucket_name
      @bucket_region = bucket_region
      @key = key
    end

    def read
      object.load
      object.get.body.read
    end

    def write(contents)
      object.put(body: StringIO.new(contents))
    end

    def delete
      object.delete
    end

    def object
      @object ||= Aws::S3::Object.new(
        bucket_name,
        key,
        client: Aws::S3::Client.new(region: bucket_region)
      )
    end

  end
end
