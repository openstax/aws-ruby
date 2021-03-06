require 'spec_helper'

RSpec.describe OpenStax::Aws::Tag do
  it "rejects nil keys" do
    expect{described_class.new(nil, "bar")}.to raise_error(/must be a non-blank/)
  end

  it "rejects keys with bad characters" do
    expect{described_class.new("?", "bar")}.to raise_error(/matching/)
  end

  it "rejects keys that are too long" do
    expect{described_class.new("a"*129, "bar")}.to raise_error(/matching/)
  end

  it "rejects keys starting with 'aws:'" do
    expect{described_class.new("aws:foo", "bar")}.to raise_error(/cannot start with 'aws/)
  end

  it "rejects values with bad characters" do
    expect{described_class.new("foo", "?")}.to raise_error(/matching/)
  end

  it "rejects values that are too long" do
    expect{described_class.new("foo", "a"*257)}.to raise_error(/matching/)
  end

  it "rejects nil values" do
    expect{described_class.new("foo", nil)}.to raise_error(/cannot be nil/)
  end

  it "allows values with blanks" do
    expect{described_class.new("foo", "a b")}.not_to raise_error
  end

  it "rejects values with commas" do
    expect{described_class.new("foo", "a,b")}.to raise_error(/matching/)
  end

  it "rejects values with semicolons" do
    expect{described_class.new("foo", "a;b")}.to raise_error(/matching/)
  end
end
