require 'spec_helper'

RSpec.describe OpenStax::Aws::ChangeSet do

  let(:client) { Aws::CloudFormation::Client.new(region: "whatever") }
  let(:instance) { described_class.new(client: client) }

  let(:action) { "Add" }
  let(:logical_resource_id) { "logical resource ID" }
  let(:physical_resource_id) { "some-aws-resource-id" }
  let(:resource_type) { "AWS::Something::Blah" }
  let(:replacement) { "False" }
  let(:scope) { ["Properties"] }
  let(:causing_entity) { nil }

  context "has description" do
    before do
      allow(instance).to receive(:description) {
        client.stub_data(
          :describe_change_set,
          changes: [{
            resource_change: {
              action: action,
              logical_resource_id: logical_resource_id,
              physical_resource_id: physical_resource_id,
              resource_type: resource_type,
              replacement: replacement,
              scope: scope,
              details: [{
                causing_entity: causing_entity
              }]
            }
          }]
        )
      }
    end

    context "has_change_caused_by?" do
      let(:causing_entity) { "foo" }

      it "says true for causes that are there" do
        expect(instance.has_change_caused_by?("foo")).to be true
      end

      it "says false for causes that are not there" do
        expect(instance.has_change_caused_by?("bar")).to be false
      end
    end

    context "Add action" do
      let(:action) { "Add" }

      it "gives change summaries" do
        expect(
          instance.resource_change_summaries[0]
        ).to eq "Add 'logical resource ID' (AWS::Something::Blah)"
      end
    end

    context "Modify action" do
      let(:action) { "Modify" }
      let(:causing_entity) { "booyah" }

      it "gives change summaries" do
        expect(
          instance.resource_change_summaries[0]
        ).to eq "Modify 'logical resource ID' (AWS::Something::Blah): Replacement=False; Due to change in [\"Properties\"]; Causes: booyah"
      end
    end
  end

end
