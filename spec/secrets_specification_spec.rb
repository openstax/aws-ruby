require 'spec_helper'

RSpec.describe OpenStax::Aws::SecretsSpecification do

  it "requires quotes around lone curly braces" do
    # curly braces have meaning in yaml (they are a mapping)
    spec = described_class.from_content(content: "foo: {{ bar }}", format: :yml)
    expect(spec.data).to eq({"foo"=>{{"bar"=>nil}=>nil}})
    expect(spec.data).not_to eq({"foo"=>"{{ bar }}"})
  end

  it "handles YAML with embedded Ruby code" do
    content = <<~CONTENT
      foo:
        <% if true %>
        bar: 42
        <% else %>
        bar: 21
        <% end %>
      production:
        bar: 84
    CONTENT
    spec = described_class.from_content(content: content, format: :yml, preparser: :erb)
  end

end
