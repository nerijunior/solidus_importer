# frozen_string_literal: true

module SolidusImporter
  module Processors
    module WooCommerce
      class Order < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          check_data
          attrs = order_attributes
          
          begin
            user = attrs.delete(:user) || Spree::User.find_by(email: attrs[:email]) || Spree::User.new(email: attrs[:email])
            SolidusImporter::SpreeCoreImporterOrder.import(user, attrs)
            context.merge!(order: attrs.merge(user: user), success: true)
          rescue => e
            context.merge!(success: false, messages: e.message)
          end
        end

        def options
          @options ||= {
            store: Spree::Store.default
          }
        end

        private

        def check_data
          raise SolidusImporter::Exception, 'Missing required key: "number"' if @data["number"].blank?
        end

        def completed_at
          date_created = @data["date_created"]
          date_created ? Time.zone.parse(date_created) : Time.current
        rescue ArgumentError
          Time.current
        end

        def currency
          @data["currency"]
        end

        def email
          # Guest orders might have email in billing instead
          @data.dig("billing", "email").presence || @data["billing_email"]
        end

        def order_attributes
          {
            number: number,
            completed_at: completed_at,
            store: options[:store],
            currency: currency,
            email: email,
            user: user,
            special_instructions: special_instruction,
            line_items_attributes: line_items_attributes,
            bill_address_attributes: build_address(@data["billing"]),
            ship_address_attributes: build_address(@data["shipping"]) || build_address(@data["billing"]),
            shipments_attributes: shipments_attributes,
            payments_attributes: payments_attributes
          }.reject { |_, v| v.blank? && v != false }
        end

        def build_address(address_data)
          return nil if address_data.blank? || address_data["first_name"].blank?
          {
            name: [address_data["first_name"], address_data["last_name"].presence].compact.join(" "),
            address1: address_data["address_1"].presence || "N/A",
            address2: address_data["address_2"],
            city: address_data["city"].presence || "N/A",
            zipcode: address_data["postcode"].presence || "00000-000",
            phone: address_data["phone"].presence || "0000000000",
            country: { 'iso' => address_data["country"] },
            state: { 'abbr' => address_data["state"] }
          }
        end

        def line_items_attributes
          (@data["line_items"] || []).each_with_index.each_with_object({}) do |(item, index), hash|
            variant = Spree::Variant.find_by(sku: item["sku"]) if item["sku"].present?
            unless variant
              product = Spree::Product.find_by(slug: item["name"].parameterize)
              variant = product.master if product
            end
            next unless variant
            
            hash[index.to_s] = {
              variant_id: variant.id,
              quantity: item["quantity"] || 1,
              price: item["price"].to_f
            }
          end
        end

        def shipments_attributes
          shipping_line = (@data["shipping_lines"] || []).first
          return [] unless shipping_line
          
          shipping_method = Spree::ShippingMethod.find_by(name: shipping_line["method_title"]) || 
                            Spree::ShippingMethod.first
          stock_location = Spree::StockLocation.first
          
          [
            {
              shipping_method: shipping_method&.name,
              stock_location: stock_location&.name,
              cost: shipping_line["total"]
            }
          ]
        end

        def payments_attributes
          payment_method = Spree::PaymentMethod.find_by(name: @data["payment_method_title"]) || 
                           Spree::PaymentMethod.first
                           
          return [] unless payment_method
          [
            {
              payment_method: payment_method.name,
              amount: @data["total"].to_f,
              state: "completed",
              source_attributes: {
                name: @data.dig("billing", "first_name").to_s,
                cc_type: "visa", # Dummy default to satisfy validation
                last_digits: "1111",
                month: "12",
                year: (Date.current.year + 1).to_s,
                gateway_payment_profile_id: "wc_#{@data['id']}"
              }
            }
          ]
        end

        def number
          @data["number"].to_s
        end

        def special_instruction
          @data["customer_note"]
        end

        def user
          @user ||= Spree::User.find_by(email: email) if email.present?
        end
      end
    end
  end
end
