module OpenStax::Aws
  class Image

    attr_reader :image

    def initialize(id:, region:)
      @image = Aws::EC2::Image.new(id, region: region)
    end

    def get_tag(key:)
      tag = image.tags.find{|tag| tag.key == key}
      raise "No tag with key #{key} on AMI #{image.image_id}" if tag.nil?
      tag.value
    end

    def sha
      get_image_tag(key: "sha")
    end

    def self.find_by_sha(sha:, region:)  
      Aws::EC2::Client.new(region: region).describe_images({
        filters: [{name: "tag:sha", values: [sha]}]
      }).images
    end
  end
end
