# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe SolidusImporter::Processors::WooCommerce::Product do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    let(:context) { {} }

    context "without product slug or name in row data" do
      let(:context) do
        {data: {"description" => "No slug or name product"}}
      end

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "slug" and "name"')
      end
    end

    context "with a valid product row" do
      let(:data) do
        {
          "slug" => "woo-album",
          "name" => "Woo Album",
          "regular_price" => "19.99",
          "status" => "publish",
          "weight" => "1.5",
          "dimensions" => {
            "length" => "10",
            "width" => "5",
            "height" => "2"
          }
        }
      end

      let(:context) { {data: data} }
      let(:product) { Spree::Product.last }
      let!(:shipping_category) { create(:shipping_category, name: "Default") }

      it "creates a new product" do
        expect { described_method }.to change(Spree::Product, :count).by(1)
        expect(product.slug).to eq("woo-album")
        expect(product.name).to eq("Woo Album")
        expect(product.price).to eq(19.99)
        expect(product.weight.to_f).to eq(1.5)
        expect(product.depth).to eq(10)
        expect(product.width).to eq(5)
        expect(product.height).to eq(2)
        expect(product).to be_available
      end

      context 'when "status" is not "publish"' do
        before { data["status"] = "draft" }

        it "creates an unavailable product" do
          described_method
          expect(product).not_to be_available
        end
      end

      context "without a price" do
        before do
          data["regular_price"] = ""
          data["price"] = ""
        end

        it "defaults price to 0" do
          described_method
          expect(product.price).to eq(0)
        end
      end

      context "with images" do
        let(:image_url) { "https://example.com/image.jpg" }
        before do
          data["images"] = [
            {"src" => image_url, "alt" => "Test Image"}
          ]
          stub_request(:get, image_url).to_return(
            status: 200,
            body: File.read(solidus_importer_fixture_path("thinking-cat.jpg")),
            headers: {'Content-Type' => 'image/jpeg'}
          )
        end

        it "attaches the images" do
          expect { described_method }.to change(Spree::Image, :count).by(1)
          expect(product.images.first.alt).to eq("Test Image")
        end
      end

      context "with an existing valid product" do
        let!(:existing_product) { create(:product, slug: data["slug"]) }

        it "updates the product" do
          expect { described_method }.not_to(change(Spree::Product, :count))
          expect(existing_product.reload.name).to eq("Woo Album")
        end
      end
    end
  end
end
