# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusImporter::Processors::WooCommerce::ProductProperties do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    let!(:shipping_category) { create(:shipping_category) }
    let!(:product) { create(:product) }

    context "with no attributes in data" do
      let(:context) { {data: {}, product: product} }

      it "does not create any properties" do
        expect { described_method }.not_to change(Spree::ProductProperty, :count)
      end
    end

    context "with attributes using an options array" do
      let(:data) do
        {
          "attributes" => [
            {"id" => 1, "name" => "Material", "options" => ["Cotton", "Polyester"]},
            {"id" => 2, "name" => "Brand", "options" => ["Acme"]}
          ]
        }
      end
      let(:context) { {data: data, product: product} }

      it "creates product properties and the underlying property records" do
        expect { described_method }
          .to change(Spree::ProductProperty, :count).by(2)
          .and change(Spree::Property, :count).by(2)
      end

      it "joins multiple options as a comma-separated value" do
        described_method
        material = product.product_properties.joins(:property)
          .find_by(spree_properties: {name: "Material"})
        expect(material.value).to eq("Cotton, Polyester")
      end

      it "stores a single option as-is" do
        described_method
        brand = product.product_properties.joins(:property)
          .find_by(spree_properties: {name: "Brand"})
        expect(brand.value).to eq("Acme")
      end
    end

    context "with an attribute using a single option string" do
      let(:data) do
        {"attributes" => [{"id" => 1, "name" => "Color", "option" => "Blue"}]}
      end
      let(:context) { {data: data, product: product} }

      it "creates a product property with the string value" do
        described_method
        prop = product.product_properties.joins(:property)
          .find_by(spree_properties: {name: "Color"})
        expect(prop.value).to eq("Blue")
      end
    end

    context "with an attribute with a blank name" do
      let(:data) do
        {"attributes" => [{"id" => 1, "name" => "", "options" => ["value"]}]}
      end
      let(:context) { {data: data, product: product} }

      it "skips the attribute" do
        expect { described_method }.not_to change(Spree::ProductProperty, :count)
      end
    end

    context "with an attribute with an empty options array and no option string" do
      let(:data) do
        {"attributes" => [{"id" => 1, "name" => "Color", "options" => []}]}
      end
      let(:context) { {data: data, product: product} }

      it "skips the attribute" do
        expect { described_method }.not_to change(Spree::ProductProperty, :count)
      end
    end

    context "when re-importing updates the existing product property value" do
      let!(:property) { create(:property, name: "Material", presentation: "Material") }
      let!(:existing_pp) do
        create(:product_property, product: product, property: property, value: "Old Value")
      end

      let(:data) do
        {"attributes" => [{"id" => 1, "name" => "Material", "options" => ["New Value"]}]}
      end
      let(:context) { {data: data, product: product} }

      it "updates in place without creating a new product property" do
        expect { described_method }.not_to change(Spree::ProductProperty, :count)
        expect(existing_pp.reload.value).to eq("New Value")
      end
    end
  end
end
