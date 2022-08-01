module OpenStax::Aws
  class Image

    attr_reader :aws_image

    def initialize(id: nil, region: nil, aws_image: nil)
      if aws_image
        @aws_image = aws_image
      else
        if id.nil? || region.nil?
          raise ArgumentError, "`id` and `region` must be provided"
        end

        @aws_image = Aws::EC2::Image.new(id, region: region)
      end
    end

    def get_tag(key:)
      tag = aws_image.tags.find{|tag| tag.key == key}
      raise "No tag with key #{key} on AMI #{aws_image.image_id}" if tag.nil?
      tag.value
    end

    def sha
      get_tag(key: "sha")
    end

    def self.find_by_sha(sha:, region:, deployment_sha: nil)
      filters = [{name: "tag:sha", values: [sha]}]
      filters << {name: "tag:deployment_sha", values: [deployment_sha]} unless deployment_sha.nil?

      Aws::EC2::Client.new(region: region).describe_images({
        owners: ['self'], filters: filters
      }).images.map{|aws_image| new(aws_image: aws_image)}
    end
  end
end
