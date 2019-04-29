require 'spec_helper'

RSpec.describe OpenStax::Aws::Template do

  context "#required_capabilities" do
    it "returns [:named_iam] if there's an IAM resource" do
      expect(new_template('one_iam_resource.yml').required_capabilities).to eq [:named_iam]
    end

    it "returns [] if there isn't an IAM resource" do
      expect(new_template('template_one.yml').required_capabilities).to eq []
    end
  end

  def new_template(filename)
    described_class.new(absolute_file_path: File.join(__dir__, "support/templates/#{filename}"),)
  end

end
