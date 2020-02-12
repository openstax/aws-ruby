require 'spec_helper'

RSpec.describe OpenStax::Aws::SecretsFactory do

  let (:instance) {
    described_class.new(region: "us-east-1", context: "foo", namespace: nil, for_create_or_update: nil)
  }

  it 'accepts a preparser argument' do
    instance.specification do
      content { "foo: <%= 42 %>" }
      format { :yml }
      preparser { :erb }
    end

    expect(instance.specification_instances[0].data).to eq ({"foo" => 42})
  end

end
