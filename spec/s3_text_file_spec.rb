require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::S3TextFile, vcr: VCR_OPTS  do

  before(:each) {
    OpenStax::Aws.configure do |config|
      config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
      config.cfn_template_bucket_region = "us-west-2"
      config.stack_waiter_delay = vcr_recording? ? 5 : 0
      config.fixed_s3_template_folder = "spec-templates"
    end
  }

  let(:region) { SPEC_DEFAULT_REGION }
  let(:bucket_name) { "aws-ruby-rspec-s3-text-file" }
  let(:stack) { new_stack(name: "s3-text-file-spec", filename: "s3_text_file/template_one.yml") }
  let(:key) { "some/path/file.json" }
  let(:test_file_path) { File.join(__dir__, "support/s3_text_file/test.json") }
  let(:test_file_string) { File.read(test_file_path) }

  it 'deletes a file' do
    with_temp_bucket(files: [{key: key, path: test_file_path}]) do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      instance.delete
      expect(file_exists?(key)).to eq false
    end
  end

  it 'does not raise for deleting a non-existent file' do
    with_temp_bucket do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      expect{instance.delete}.not_to raise_error
    end
  end

  it 'reads a file' do
    with_temp_bucket(files: [{key: key, path: test_file_path}]) do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      expect(instance.read).to eq test_file_string
    end
  end

  it 'raises for reading a non-existent file' do
    with_temp_bucket do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      expect{instance.read}.to raise_error(Aws::S3::Errors::NotFound)
    end
  end

  it 'writes a new file' do
    with_temp_bucket do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      instance.write(string_contents: test_file_string)
      expect(instance.read).to eq test_file_string
      instance.delete
    end
  end

  it 'overwrites a file' do
    with_temp_bucket(files: [{key: key, path: test_file_path}]) do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      instance.write(string_contents: "something new")
      expect(instance.read).to eq "something new"
    end
  end

  it 'sets the cache control header' do
    with_temp_bucket(files: [{key: key, path: test_file_path}]) do
      instance = described_class.new(bucket_name: bucket_name, bucket_region: region, key: key)
      instance.write(string_contents: "something new", cache_control: "max-age=0")
      expect(instance.get.cache_control).to eq "max-age=0"
    end
  end

  def with_temp_bucket(files: [])
    begin
      do_not_record_or_playback do
        stack.create(params: {bucket_name: bucket_name}, wait: true)
        files.each do |file|
          upload_file(key: file[:key], filename: file[:path])
        end
      end

      yield
    ensure
      do_not_record_or_playback do
        files.each do |file|
          delete_file(key: file[:key]) rescue nil
        end
        stack.delete(wait: true)
      end
    end
  end

  def upload_file(key:, filename:)
    s3 = Aws::S3::Resource.new(region: region)
    obj = s3.bucket(bucket_name).object(key)
    obj.upload_file(filename)
  end

  def delete_file(key:)
    s3 = Aws::S3::Resource.new(region: region)
    obj = s3.bucket(bucket_name).object(key)
    obj.delete
  end

  def file_exists?(key)
    begin
      Aws::S3::Client.new(region: region).get_object(bucket: bucket_name, key: key)
      true
    rescue Aws::S3::Errors::NoSuchKey
      false
    end
  end
end
