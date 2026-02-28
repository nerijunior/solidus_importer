# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusImporter::Processors::WooCommerce::Category do
  describe "#call" do
    subject(:described_method) { described_class.call(context) }

    context "without id in row data" do
      let(:context) { {data: {"name" => "Shoes"}} }

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "id"')
      end
    end

    context "without name in row data" do
      let(:context) { {data: {"id" => 1}} }

      it "raises an exception" do
        expect { described_method }.to raise_error(SolidusImporter::Exception, 'Missing required key: "name"')
      end
    end

    context "with a valid top-level category (parent: 0)" do
      let(:data) { {"id" => 1, "name" => "Roupas", "parent" => 0} }
      let(:context) { {data: data} }

      it "creates the Categorias taxonomy if it does not exist" do
        expect { described_method }.to change(Spree::Taxonomy, :count).by(1)
        expect(Spree::Taxonomy.find_by(name: "Categorias")).to be_present
      end

      it "creates a taxon under the taxonomy root" do
        described_method
        taxon = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:1")
        expect(taxon).to be_present
        expect(taxon.name).to eq("Roupas")
        expect(taxon.parent).to eq(Spree::Taxonomy.find_by(name: "Categorias").root)
      end

      it "stores the WooCommerce id in meta_keywords" do
        described_method
        taxon = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:1")
        expect(taxon.meta_keywords).to eq("wc_id:1")
      end

      it "adds the taxon to the context" do
        result = described_method
        expect(result[:taxon]).to be_a(Spree::Taxon)
        expect(result[:taxon].name).to eq("Roupas")
      end
    end

    context "with a child category whose parent already exists" do
      let!(:taxonomy) { Spree::Taxonomy.find_or_create_by!(name: "Categorias") }
      let!(:parent_taxon) do
        Spree::Taxon.create!(
          name: "Roupas",
          taxonomy: taxonomy,
          parent: taxonomy.root,
          meta_keywords: "wc_id:5"
        )
      end

      let(:data) { {"id" => 10, "name" => "Camisetas", "parent" => 5} }
      let(:context) { {data: data} }

      it "creates the child taxon under the correct parent" do
        expect { described_method }.to change(Spree::Taxon, :count).by(1)
        child = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:10")
        expect(child.parent).to eq(parent_taxon)
      end
    end

    context "with a child category whose parent does not exist" do
      let(:data) { {"id" => 10, "name" => "Camisetas", "parent" => 99} }
      let(:context) { {data: data} }

      it "falls back to the taxonomy root" do
        described_method
        taxon = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:10")
        expect(taxon.parent).to eq(Spree::Taxonomy.find_by(name: "Categorias").root)
      end
    end

    context "when re-importing an existing category" do
      let!(:taxonomy) { Spree::Taxonomy.find_or_create_by!(name: "Categorias") }
      let!(:existing) do
        Spree::Taxon.create!(
          name: "Old Name",
          taxonomy: taxonomy,
          parent: taxonomy.root,
          meta_keywords: "wc_id:1"
        )
      end

      let(:data) { {"id" => 1, "name" => "New Name", "parent" => 0} }
      let(:context) { {data: data} }

      it "updates the existing taxon without creating a new one" do
        expect { described_method }.not_to change(Spree::Taxon, :count)
        expect(existing.reload.name).to eq("New Name")
      end
    end
  end
end
