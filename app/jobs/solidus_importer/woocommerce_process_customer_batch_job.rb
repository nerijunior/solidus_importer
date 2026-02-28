# frozen_string_literal: true

module SolidusImporter
  class WoocommerceProcessCustomerBatchJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked
    discard_on ActiveRecord::RecordNotFound

    BATCH_SIZE = 50

    def perform(import_id:, row_ids:)
      import = ::SolidusImporter::Import.find(import_id)

      importer_options = SolidusImporter::Config.solidus_importer[:woocommerce_customers]
      raise SolidusImporter::Exception, "No importer config found for woocommerce_customers" unless importer_options

      importer = importer_options[:importer].new(importer_options)
      import.importer = importer
      initial_context = importer.before_import({ success: true })

      SolidusImporter::Row.where(id: row_ids).each do |row|
        SolidusImporter::ProcessRow.new(importer, row).process(initial_context)
        if row.reload.state == "failed"
          puts "[WooCommerce] Error on woocommerce_customers ID #{row.data['id']}: #{row.messages}"
        end
      end
    end
  end
end
