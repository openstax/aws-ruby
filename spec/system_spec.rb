require 'spec_helper'

RSpec.describe OpenStax::Aws::System do

  it "propagates exit codes" do
    expect{described_class.call("exit 1", dry_run: false)}.to raise_error do |error|
      expect(error).to be_a(SystemExit)
      expect(error.status).to eq 1
    end
  end

  it "does not exit when all good" do
    expect{described_class.call("sleep 0", dry_run: false)}.not_to raise_error
  end

end
