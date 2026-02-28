# frozen_string_literal: true

module SolidusImporter
  module Processors
    module WooCommerce
      class Customer < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          check_data
          context.merge!(user: process_user)
        end

        def options
          @options ||= {
            password_method: ->(user) { user.password = user.password_confirmation = SecureRandom.hex(8) }
          }
        end

        private

        def check_data
          raise SolidusImporter::Exception, 'Missing required key: "email"' if @data["email"].blank?
        end

        def prepare_user
          Spree::User.find_or_initialize_by(email: @data["email"])
        end

        def process_user
          prepare_user.tap do |user|
            options[:password_method].call(user) if user.new_record? && user.password.blank?
            user.save!

            attach_user_address(user, @data["billing"], default_shipping: false, default_billing: true)
            attach_user_address(user, @data["shipping"], default_shipping: true, default_billing: false)
          end
        end

        def attach_user_address(user, address_data, default_shipping:, default_billing:)
          return if address_data.blank? || address_data["address_1"].blank?
          return if address_data["first_name"].blank?

          country = Spree::Country.find_by(iso: address_data["country"]&.upcase)
          return unless country

          state = Spree::State.find_by(abbr: address_data["state"]&.upcase, country: country) ||
                  Spree::State.find_by(name: address_data["state"], country: country)

          attrs = {
            name: [address_data["first_name"], address_data["last_name"].presence].compact.join(" "),
            address1: address_data["address_1"].presence || "N/A",
            address2: address_data["address_2"].presence,
            city: address_data["city"].presence || "N/A",
            zipcode: address_data["postcode"].presence || "00000-000",
            phone: address_data["phone"].presence || "0000000000",
            country_id: country.id
          }

          if state
            attrs[:state_id] = state.id
          elsif address_data["state"].present?
            attrs[:state_name] = address_data["state"]
          end

          address = Spree::Address.factory(attrs)
          address.save! unless address.persisted?

          return if user.user_addresses.exists?(address_id: address.id)

          user.user_addresses.create!(
            address: address,
            default: default_shipping,
            default_billing: default_billing
          )
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("[WooCommerce] Could not create address for #{user.email}: #{e.message}")
        end
      end
    end
  end
end
