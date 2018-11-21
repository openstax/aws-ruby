RSpec.describe OpenStax::Aws::ParametersSpecification do

  it "requires quotes around lone curly braces" do
    # curly braces have meaning in yaml (they are a mapping)
    spec = described_class.from_content(content: "foo: {{ bar }}", format: :yml)
    expect(spec.data).to eq {"foo"=>{{"bar"=>nil}=>nil}}
    expect(spec.data).not_to eq {"foo"=>"{{ bar }}"}
  end

end
