# frozen_string_literal: true

module SolidusImporter
  module Processors
    module WooCommerce
      class ProductProperties < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          product = context.fetch(:product)
          process_properties(product)
        end

        private

        def process_properties(product)
          attributes = @data["attributes"]
          return if attributes.blank?

          attributes.each_with_index do |attr, index|
            name = attr["name"].presence
            next if name.blank?

            value = extract_value(attr)
            next if value.blank?

            property = Spree::Property.find_or_create_by!(name: name) do |p|
              p.presentation = name
            end

            product_property = product.product_properties.find_or_initialize_by(property: property)
            product_property.value = value
            product_property.position = index
            product_property.save!
          end
        end

        # WooCommerce uses "options" (Array) for product-level attributes
        # and "option" (String) for variation-level attributes.
        def extract_value(attr)
          options = attr["options"]
          if options.is_a?(Array) && options.any?
            options.join(", ")
          else
            attr["option"].presence
          end
        end
      end
    end
  end
end
