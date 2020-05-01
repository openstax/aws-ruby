require 'spec_helper'
require 'vcr_helper'

# the image that is being used in tests
# was created manually in aws console 

RSpec.describe OpenStax::Aws::Image, vcr: VCR_OPTS do
  let(:region) { SPEC_DEFAULT_REGION }
  let(:test_image_id) { 'ami-06130829ed7f50ca1' }
  let(:test_image_sha) { 'randomSha' }

  let (:instance) {
    described_class.new(id: test_image_id, region: SPEC_DEFAULT_REGION)
  }

  context "#find_by_sha" do 
    it "finds images" do
      images = described_class.find_by_sha(sha: test_image_sha, region: region)

      expect(images.length).to be(1)
      expect(images[0].aws_image[:image_id]).to eq(test_image_id)
    end
  end

  context "#sha" do
    it "finds sha for given ami id" do
      expect(instance.sha).to eq(test_image_sha)
    end
  end
end
