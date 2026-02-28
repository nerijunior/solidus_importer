# frozen_string_literal: true

module SolidusImporter
  module Processors
    module WooCommerce
      class Category < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          check_data
          context.merge!(taxon: process_category)
        end

        private

        def check_data
          raise SolidusImporter::Exception, 'Missing required key: "id"' if @data["id"].blank?
          raise SolidusImporter::Exception, 'Missing required key: "name"' if @data["name"].blank?
        end

        def taxonomy
          @taxonomy ||= Spree::Taxonomy.find_or_create_by!(name: "Categorias")
        end

        def process_category
          wc_id = @data["id"].to_i
          parent_taxon = find_parent_taxon

          taxon = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:#{wc_id}")

          if taxon
            taxon.name = @data["name"]
            taxon.parent = parent_taxon
            taxon.taxonomy = taxonomy
          else
            taxon = Spree::Taxon.new(
              name: @data["name"],
              taxonomy: taxonomy,
              parent: parent_taxon,
              meta_keywords: "wc_id:#{wc_id}"
            )
          end

          taxon.save!
          taxon
        end

        def find_parent_taxon
          parent_id = @data["parent"].to_i
          return taxonomy.root if parent_id.zero?

          Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:#{parent_id}") || taxonomy.root
        end
      end
    end
  end
end
