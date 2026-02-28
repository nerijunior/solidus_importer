# frozen_string_literal: true

module SolidusImporter
  class SpreeCoreImporterOrder < Spree::Core::Importer::Order
    # Ensure the variant has a price in the order's currency before adding it
    # to the order. If no price exists, create one using the WooCommerce price.
    # This prevents "Price is not valid" errors from order.contents.add when
    # the variant was imported with a different default currency.
    def self.create_line_item(line_item_hash, order)
      price = line_item_hash[:price]
      if price.present?
        variant = Spree::Variant.find(line_item_hash[:variant_id])
        pricing_options = Spree::Config.pricing_options_class.new(currency: order.currency)
        unless variant.price_for_options(pricing_options)
          variant.prices.create!(amount: price, currency: order.currency)
        end
      end
      super
    end

    def self.import(user, params)
      params = params.to_h
      ActiveRecord::Base.transaction do
        ensure_country_id_from_params params[:ship_address_attributes]
        ensure_state_id_from_params params[:ship_address_attributes]
        ensure_country_id_from_params params[:bill_address_attributes]
        ensure_state_id_from_params params[:bill_address_attributes]

        create_params = params.slice :currency
        order = Spree::Order.create! create_params
        order.store ||= Spree::Store.default
        order.associate_user!(user)
        order.save!

        shipments_attrs = params.delete(:shipments_attributes)

        create_line_items_from_params(params.delete(:line_items_attributes), order)
        create_shipments_from_params(shipments_attrs, order)
        create_adjustments_from_params(params.delete(:adjustments_attributes), order)
        create_payments_from_params(params.delete(:payments_attributes), order)

        params.delete(:user_id) unless user.try(:has_spree_role?, "admin") && params.key?(:user_id)

        completed_at = params.delete(:completed_at)

        order.update!(params)

        order.create_proposed_shipments if shipments_attrs.blank?

        if completed_at
          order.completed_at = completed_at
          order.state = "complete"
          order.save!
        end

        # Really ensure that the order totals & states are correct
        tax_adjuster_class = Spree::Config.tax_adjuster_class
        Spree::Config.tax_adjuster_class = SolidusImporter::Tax::NullOrderAdjuster

        order.updater.update
        if shipments_attrs.present?
          order.shipments.each_with_index do |shipment, index|
            shipment.update_columns(cost: shipments_attrs[index][:cost].to_f) if shipments_attrs[index][:cost].present?
          end
        end
        order.reload

        Spree::Config.tax_adjuster_class = tax_adjuster_class
      end
    end
  end
end
