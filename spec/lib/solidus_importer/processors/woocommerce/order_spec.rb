# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusImporter::Processors::WooCommerce::Order do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    let(:context) { {} }

    context "without order number in row data" do
      let(:context) do
        {data: {"status" => "processing"}}
      end

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "number"')
      end
    end

    context "with a valid order row" do
      let(:data) do
        {
          "number" => "1234",
          "date_created" => "2023-01-01T12:00:00",
          "currency" => "USD",
          "customer_note" => "Please leave at door",
          "billing" => {
            "email" => "customer@example.com"
          }
        }
      end

      let(:context) { {data: data} }

      it "returns a valid order context" do
        allow(SolidusImporter::SpreeCoreImporterOrder).to receive(:import).and_return(true)
        result = described_method
        expect(result[:order]).to be_a(Hash)
        expect(result[:order][:number]).to eq("1234")
        expect(result[:order][:currency]).to eq("USD")
        expect(result[:order][:email]).to eq("customer@example.com")
        expect(result[:order][:special_instructions]).to eq("Please leave at door")
      end

      context "when a user exists with the email" do
        let!(:user) { create(:user, email: "customer@example.com") }

        it "associates the user" do
          allow(SolidusImporter::SpreeCoreImporterOrder).to receive(:import).and_return(true)
          result = described_method
          expect(result[:order][:user]).to eq(user)
        end
      end
    end
  end
end
