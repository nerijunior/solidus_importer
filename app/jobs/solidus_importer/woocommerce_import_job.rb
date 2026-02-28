# frozen_string_literal: true

module SolidusImporter
  class WoocommerceImportJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked

    def perform(import_id:, url:, consumer_key:, consumer_secret:, endpoint:, import_type:, order_statuses: nil)
      import = ::SolidusImporter::Import.find(import_id)

      fetcher = ::SolidusImporter::WooCommerce::Fetcher.new(
        url: url,
        consumer_key: consumer_key,
        consumer_secret: consumer_secret
      )

      if import_type == 'woocommerce_customers'
        fetcher.fetch_and_schedule(import, endpoint: endpoint)
      elsif import_type == 'woocommerce_categories'
        fetcher.fetch_and_process_categories(import, endpoint: endpoint)
      elsif import_type == 'woocommerce_attributes'
        fetcher.fetch_and_process_attributes(import, endpoint: endpoint)
      else
        fetcher.fetch_and_process(import, endpoint: endpoint, order_statuses: order_statuses)
      end
    end
  end
end
