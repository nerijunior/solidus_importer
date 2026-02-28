# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe SolidusImporter::WooCommerce::Fetcher do
  let(:url) { "https://example.com" }
  let(:consumer_key) { "ck_123" }
  let(:consumer_secret) { "cs_123" }
  let(:fetcher) { described_class.new(url: url, consumer_key: consumer_key, consumer_secret: consumer_secret) }

  describe "#fetch_and_import" do
    let(:endpoint) { "/wp-json/wc/v3/products" }
    let(:import_type) { :woocommerce_products }
    
    context "with a successful API response" do
      let(:response_body) do
        [{ "id" => 1, "name" => "Woo Product", "slug" => "woo-product", "status" => "publish", "regular_price" => "19.99" }]
      end

      let!(:shipping_category) { create(:shipping_category, name: "Default") }

      before do
        stub_request(:get, "#{url}#{endpoint}?page=1&per_page=100")
          .with(basic_auth: [consumer_key, consumer_secret])
          .to_return(status: 200, body: response_body.to_json, headers: {"Content-Type" => "application/json"})
      end

      it "fetches data and creates an import" do
        expect {
          fetcher.fetch_and_import(endpoint: endpoint, import_type: import_type)
        }.to change(SolidusImporter::Import, :count).by(1)
         .and change(SolidusImporter::Row, :count).by(1)
         
        import = SolidusImporter::Import.last
        expect(import.import_type).to eq("woocommerce_products")
        expect(import.state).to eq("completed")
      end
    end

    context "with a failed API response" do
      before do
        stub_request(:get, "#{url}#{endpoint}?page=1&per_page=100")
          .with(basic_auth: [consumer_key, consumer_secret])
          .to_return(status: 401, body: '{"code":"woocommerce_rest_cannot_view","message":"Sorry, you cannot list resources."}', headers: {"Content-Type" => "application/json"})
      end

      it "raises an exception" do
        expect {
          fetcher.fetch_and_import(endpoint: endpoint, import_type: import_type)
        }.to raise_error(SolidusImporter::Exception, /WooCommerce API error: 401/)
      end
    end
  end
end
