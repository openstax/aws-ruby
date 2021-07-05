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

  context "#is_sam?" do
    it "returns true for sam templates" do
      expect(new_template("sam_simple.yml").is_sam?).to be true
    end

    it "returns true for sam templates with quotes" do
      expect(new_template("sam_simple_two.yml").is_sam?).to be true
    end

    it "returns false for non-sam templates" do
      expect(new_template('template_one.yml').is_sam?).to be false
    end
  end

  def new_template(filename)
    described_class.new(absolute_file_path: File.join(__dir__, "support/templates/#{filename}"),)
  end

end
