# frozen_string_literal: true

require "faraday"
require "json"

module SolidusImporter
  module WooCommerce
    class Fetcher
      def initialize(url:, consumer_key:, consumer_secret:)
        @url = url
        @consumer_key = consumer_key
        @consumer_secret = consumer_secret
      end

      def fetch_and_process(import, endpoint:, options: {}, order_statuses: nil)
        ensure_import_file!(import)
        import.update!(state: :processing)

        importer_options = SolidusImporter::Config.solidus_importer[import.import_type.to_sym]
        raise SolidusImporter::Exception, "No importer config found for type: #{import.import_type}" unless importer_options
        
        importer = importer_options[:importer].new(importer_options)
        import.importer = importer
        initial_context = importer.before_import({ success: true })

        fetch_options = order_fetch_options(import.import_type, order_statuses)

        total_processed = 0
        fetch_data(endpoint, fetch_options) do |batch|
          rows = batch.map do |item|
            SolidusImporter::Row.create!(import: import, data: item)
          end

          rows.each_with_index do |row, index|
            SolidusImporter::ProcessRow.new(importer, row).process(initial_context)
            if row.reload.state == "failed"
              puts "[WooCommerce] Error on #{import.import_type} ID #{row.data['id']}: #{row.messages}"
            end
            total_processed += 1
            if (total_processed % 10).zero?
              puts "[WooCommerce] Processed #{total_processed} #{import.import_type.split('_').last}..."
            end
          end
        end
        
        if total_processed.zero?
          import.update!(state: :completed, messages: "No API data found")
          return import
        end

        ending_context = importer.after_import(initial_context)
        
        state = import.reload.rows.failed.any? ? :failed : :completed
        state = :failed if ending_context[:success] == false
        
        messages = ending_context[:messages].try(:join, ", ")
        
        import.update!(state: state, messages: messages)
        puts "[WooCommerce] Completed importing #{total_processed} items. State is #{state}!"
        import
      end

      # Fetches all category pages, sorts them topologically (parents before
      # children), creates all Row records, then processes them in order so that
      # parent taxons always exist before children are linked to them.
      def fetch_and_process_categories(import, endpoint:)
        ensure_import_file!(import)
        import.update!(state: :processing)

        importer_options = SolidusImporter::Config.solidus_importer[:woocommerce_categories]
        raise SolidusImporter::Exception, "No importer config found for woocommerce_categories" unless importer_options

        importer = importer_options[:importer].new(importer_options)
        import.importer = importer
        initial_context = importer.before_import({ success: true })

        all_categories = []
        fetch_data(endpoint) do |batch|
          all_categories.concat(batch)
        end

        if all_categories.empty?
          import.update!(state: :completed, messages: "No categories found")
          return import
        end

        sorted = sort_topologically(all_categories)

        # Create ALL rows before processing so import.finished? counts correctly
        rows = sorted.map { |item| SolidusImporter::Row.create!(import: import, data: item) }
        puts "[WooCommerce] Processing #{rows.size} categories..."

        rows.each do |row|
          SolidusImporter::ProcessRow.new(importer, row).process(initial_context)
          if row.reload.state == "failed"
            puts "[WooCommerce] Error on category ID #{row.data['id']}: #{row.messages}"
          end
        end

        ending_context = importer.after_import(initial_context)

        state = import.reload.rows.failed.any? ? :failed : :completed
        state = :failed if ending_context[:success] == false

        messages = ending_context[:messages].try(:join, ", ")
        import.update!(state: state, messages: messages)
        puts "[WooCommerce] Completed importing #{rows.size} categories. State is #{state}!"
        import
      end

      # Fetches all pages, creates Row records, then enqueues a batch processing
      # job per slice. Used for large datasets (e.g. customers) so each batch
      # runs independently and can be retried without reprocessing everything.
      def fetch_and_schedule(import, endpoint:)
        ensure_import_file!(import)
        import.update!(state: :processing)

        all_row_ids = []
        fetch_data(endpoint) do |batch|
          ids = batch.map { |item| SolidusImporter::Row.create!(import: import, data: item).id }
          all_row_ids.concat(ids)
        end

        if all_row_ids.empty?
          import.update!(state: :completed, messages: "No API data found")
          return import
        end

        puts "[WooCommerce] Scheduling #{all_row_ids.size} customer(s) across #{(all_row_ids.size.to_f / WoocommerceProcessCustomerBatchJob::BATCH_SIZE).ceil} job(s)..."

        all_row_ids.each_slice(WoocommerceProcessCustomerBatchJob::BATCH_SIZE) do |batch_ids|
          ::SolidusImporter::WoocommerceProcessCustomerBatchJob.perform_later(
            import_id: import.id,
            row_ids: batch_ids
          )
        end

        import
      end

      # Fetches all global WooCommerce attributes, enriches each with its terms
      # (option values), then creates and processes rows so the Attribute processor
      # has everything it needs to build OptionTypes + OptionValues.
      def fetch_and_process_attributes(import, endpoint:)
        ensure_import_file!(import)
        import.update!(state: :processing)

        importer_options = SolidusImporter::Config.solidus_importer[:woocommerce_attributes]
        raise SolidusImporter::Exception, "No importer config found for woocommerce_attributes" unless importer_options

        importer = importer_options[:importer].new(importer_options)
        import.importer = importer
        initial_context = importer.before_import({ success: true })

        all_attributes = []
        fetch_data(endpoint) do |batch|
          batch.each do |attr|
            terms = []
            fetch_data("#{endpoint}/#{attr['id']}/terms") { |t| terms.concat(t) }
            all_attributes << attr.merge("terms" => terms)
          end
        end

        if all_attributes.empty?
          import.update!(state: :completed, messages: "No attributes found")
          return import
        end

        rows = all_attributes.map { |item| SolidusImporter::Row.create!(import: import, data: item) }
        puts "[WooCommerce] Processing #{rows.size} attributes..."

        rows.each do |row|
          SolidusImporter::ProcessRow.new(importer, row).process(initial_context)
          if row.reload.state == "failed"
            puts "[WooCommerce] Error on attribute ID #{row.data['id']}: #{row.messages}"
          end
        end

        ending_context = importer.after_import(initial_context)

        state = import.reload.rows.failed.any? ? :failed : :completed
        state = :failed if ending_context[:success] == false

        messages = ending_context[:messages].try(:join, ", ")
        import.update!(state: state, messages: messages)
        puts "[WooCommerce] Completed importing #{rows.size} attributes. State is #{state}!"
        import
      end

      def fetch_and_import(endpoint:, import_type:, options: {})
        import = SolidusImporter::Import.new(import_type: import_type)
        fetch_and_process(import, endpoint: endpoint, options: options)
      end

      private

      def sort_topologically(items)
        result = []
        remaining = items.dup
        max_iterations = items.size + 1
        iterations = 0

        while remaining.any? && iterations < max_iterations
          processable = remaining.select do |item|
            item["parent"].to_i.zero? || result.any? { |r| r["id"].to_i == item["parent"].to_i }
          end
          break if processable.empty?

          result.concat(processable)
          remaining -= processable
          iterations += 1
        end

        # Safety: append orphaned items (handles unexpected API data)
        result.concat(remaining)
        result
      end

      def ensure_import_file!(import)
        return if import.file.present?

        temp_file = Tempfile.new(["woocommerce_#{import.import_type}", ".csv"])
        temp_file.write(JSON.dump([]))
        temp_file.rewind
        import.file = temp_file
        import.save!
        temp_file.close
        temp_file.unlink
      end

      def client
        @client ||= Faraday.new(url: @url) do |conn|
          conn.request :authorization, :basic, @consumer_key, @consumer_secret
          conn.response :json, content_type: /\bjson$/
        end
      end

      ORDER_STATUSES = %w[wc-pending wc-processing wc-on-hold wc-completed wc-pedido-enviado].freeze

      def order_fetch_options(import_type, order_statuses = nil)
        return {} unless import_type.to_s.include?("order")

        statuses = order_statuses.presence || ORDER_STATUSES.join(",")
        { status: statuses }
      end

      DEBUG_LIMIT = ENV.fetch('IMPORTER_LIMIT', nil) # Set to nil to disable

      def fetch_data(endpoint, extra_params = {})
        page = 1
        per_page = DEBUG_LIMIT || 100

        loop do
          puts "[WooCommerce] Fetching #{endpoint} (page #{page})..."
          response = client.get(endpoint, { page: page, per_page: per_page }.merge(extra_params))

          unless response.success?
            raise SolidusImporter::Exception, "WooCommerce API error: #{response.status} - #{response.body}"
          end

          body = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
          batch = body.is_a?(Array) ? body : [body].compact

          break if batch.empty?

          yield batch

          break if DEBUG_LIMIT # Stop after first page when debugging
          break if batch.length < per_page
          break if page >= 50 # Failsafe against infinite loops

          page += 1
        end
      end
    end
  end
end
