# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusImporter::Processors::WooCommerce::Attribute do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    context "without name in row data" do
      let(:context) { {data: {"id" => 1}} }

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "name"')
      end
    end

    context "with a valid attribute and terms" do
      let(:data) do
        {
          "id" => 1,
          "name" => "Color",
          "terms" => [
            {"id" => 1, "name" => "Red"},
            {"id" => 2, "name" => "Blue"}
          ]
        }
      end
      let(:context) { {data: data} }

      it "creates an option type with a parameterized name" do
        expect { described_method }.to change(Spree::OptionType, :count).by(1)
        option_type = Spree::OptionType.find_by(name: "color")
        expect(option_type).to be_present
        expect(option_type.presentation).to eq("Color")
      end

      it "creates an option value for each term" do
        expect { described_method }.to change(Spree::OptionValue, :count).by(2)
        option_type = Spree::OptionType.find_by(name: "color")
        expect(option_type.option_values.map(&:presentation)).to contain_exactly("Red", "Blue")
      end

      it "adds the option_type to the context" do
        result = described_method
        expect(result[:option_type]).to be_a(Spree::OptionType)
        expect(result[:option_type].name).to eq("color")
      end
    end

    context "with no terms" do
      let(:data) { {"id" => 1, "name" => "Material", "terms" => []} }
      let(:context) { {data: data} }

      it "creates the option type with no option values" do
        expect { described_method }.to change(Spree::OptionType, :count).by(1)
        expect(Spree::OptionType.find_by(name: "material").option_values).to be_empty
      end
    end

    context "when re-importing an existing attribute" do
      let!(:existing) { create(:option_type, name: "color", presentation: "Old Color") }
      let(:data) { {"id" => 1, "name" => "Color", "terms" => []} }
      let(:context) { {data: data} }

      it "updates the presentation without creating a new option type" do
        expect { described_method }.not_to change(Spree::OptionType, :count)
        expect(existing.reload.presentation).to eq("Color")
      end
    end

    context "when re-importing an existing term" do
      let!(:existing_type) { create(:option_type, name: "color", presentation: "Color") }
      let!(:existing_value) do
        create(:option_value, name: "red", presentation: "Old Red", option_type: existing_type)
      end

      let(:data) do
        {
          "id" => 1,
          "name" => "Color",
          "terms" => [{"id" => 1, "name" => "Red"}]
        }
      end
      let(:context) { {data: data} }

      it "updates the existing option value without creating a new one" do
        expect { described_method }.not_to change(Spree::OptionValue, :count)
        expect(existing_value.reload.presentation).to eq("Red")
      end
    end
  end
end
