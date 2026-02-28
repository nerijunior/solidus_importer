# frozen_string_literal: true

module SolidusImporter
  module Processors
    module WooCommerce
      class Attribute < SolidusImporter::Processors::Base
        def call(context)
          @data = context.fetch(:data)
          check_data
          option_type = process_option_type
          process_option_values(option_type)
          context.merge!(option_type: option_type)
        end

        private

        def check_data
          raise SolidusImporter::Exception, 'Missing required key: "name"' if @data["name"].blank?
        end

        def process_option_type
          internal_name = @data["name"].downcase.parameterize
          Spree::OptionType.find_or_initialize_by(name: internal_name).tap do |ot|
            ot.presentation = @data["name"]
            ot.save!
          end
        end

        def process_option_values(option_type)
          terms = @data["terms"] || []
          terms.each_with_index do |term, position|
            internal_name = term["name"].downcase.parameterize
            Spree::OptionValue.find_or_initialize_by(name: internal_name, option_type: option_type).tap do |ov|
              ov.presentation = term["name"]
              ov.position = position
              ov.save!
            end
          end
        end
      end
    end
  end
end
