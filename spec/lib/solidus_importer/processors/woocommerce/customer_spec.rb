# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusImporter::Processors::WooCommerce::Customer do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    let(:context) { {} }

    context "without email in row data" do
      let(:context) do
        {data: {"first_name" => "John"}}
      end

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "email"')
      end
    end

    context "with a valid customer row" do
      let(:data) do
        {
          "email" => "john.doe@example.com",
          "first_name" => "John",
          "last_name" => "Doe"
        }
      end

      let(:context) { {data: data} }
      let(:user) { Spree::User.last }

      it "creates a new user" do
        expect { described_method }.to change(Spree::User, :count).by(1)
        expect(user.email).to eq("john.doe@example.com")
      end

      context "with an existing valid customer" do
        let!(:existing_user) { create(:user, email: data["email"]) }

        it "does not create a duplicate user" do
          expect { described_method }.not_to(change(Spree::User, :count))
        end
      end
    end
  end
end
