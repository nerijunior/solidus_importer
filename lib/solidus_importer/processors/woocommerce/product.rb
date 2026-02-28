# frozen_string_literal: true

require 'open-uri'

module SolidusImporter
  module Processors
    module WooCommerce
      class Product < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          check_data
          product = process_product
          attach_taxons(product)
          context.merge!(product: product)
        end

        def options
          @options ||= {
            shipping_category: Spree::ShippingCategory.find_by(name: "Default") || Spree::ShippingCategory.first
          }
        end

        private

        def check_data
          @data["slug"] = @data["name"].parameterize if @data["slug"].blank? && @data["name"].present?
          raise SolidusImporter::Exception, 'Missing required key: "slug" and "name"' if @data["slug"].blank?
        end

        def prepare_product
          Spree::Product.find_or_initialize_by(slug: @data["slug"])
        end

        def process_product
          prepare_product.tap do |product|
            product.slug = @data["slug"]
            product.name = @data["name"]

            if @data["regular_price"].present?
              product.price = @data["regular_price"]
            elsif @data["price"].present?
              product.price = @data["price"]
            else
              product.price = 0
            end

            product.description = clean_description(@data["short_description"].presence || @data["description"].presence)
            product.available_on = available? ? Date.current.yesterday : nil
            product.shipping_category = options[:shipping_category] if product.shipping_category.nil?

            # Weight and dimensions if available
            product.weight = @data["weight"] if @data["weight"].present?
            product.height = @data["dimensions"]["height"] if @data.dig("dimensions", "height").present?
            product.width = @data["dimensions"]["width"] if @data.dig("dimensions", "width").present?
            product.depth = @data["dimensions"]["length"] if @data.dig("dimensions", "length").present? # WC uses length for depth

            if @data["images"].present? && @data["images"].is_a?(Array) && product.images.none?
              @data["images"].each_with_index do |image_data, index|
                begin
                  attachment = URI.parse(image_data["src"]).open
                  image = Spree::Image.new(
                    attachment: attachment,
                    alt: image_data["alt"].presence || @data["name"],
                    position: index + 1
                  )
                  product.images << image
                rescue StandardError => e
                  # Continue with other images if one fails to download
                end
              end
            end

            product.save!
          end
        end

        def attach_taxons(product)
          categories = @data["categories"]
          return if categories.blank?

          categories.each do |cat|
            taxon = Spree::Taxon.find_by("meta_keywords LIKE ?", "wc_id:#{cat['id']}")
            next unless taxon

            product.taxons << taxon unless product.taxons.include?(taxon)
          end
        end

        def clean_description(html)
          return nil if html.blank?

          html
            .gsub(/<br\s*\/?>/, "\n")  # convert <br> to newlines before stripping tags
            .then { |s| ActionController::Base.helpers.strip_tags(s) }
            .gsub(/\[[^\]]*\]/, '')    # strip WordPress shortcodes like [vc_row]
            .gsub(/\n{3,}/, "\n\n")   # collapse excessive blank lines
            .gsub(/[ \t]+/, ' ')      # collapse horizontal whitespace only
            .strip
            .presence
        end

        def available?
          @data["status"] == "publish"
        end
      end
    end
  end
end
