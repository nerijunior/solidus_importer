# frozen_string_literal: true

module Spree
  module Admin
    module SolidusImporter
      class ImportsController < ResourceController
        before_action :assigns_import_types
        after_action :import!, if: -> { @import&.valid? && !@import.import_type.to_s.start_with?('woocommerce') }, only: :create

        def create
          import_type = params.dig(:solidus_importer_import, :import_type)
          if import_type.to_s.start_with?('woocommerce')
            begin
              endpoint = case import_type
                         when 'woocommerce_products' then '/wp-json/wc/v3/products'
                         when 'woocommerce_orders' then '/wp-json/wc/v3/orders'
                         when 'woocommerce_customers' then '/wp-json/wc/v3/customers'
                         when 'woocommerce_categories' then '/wp-json/wc/v3/products/categories'
                         when 'woocommerce_attributes' then '/wp-json/wc/v3/products/attributes'
                         end
              # Create a placeholder Import record
              temp_file = Tempfile.new(["woocommerce_#{import_type}", ".csv"])
              temp_file.write("status\nfetching_from_api")
              temp_file.rewind

              import = ::SolidusImporter::Import.new(
                import_type: import_type,
                state: :created,
                file: temp_file
              )
              import.save!
              temp_file.close
              temp_file.unlink

              job_args = {
                import_id: import.id,
                url: params[:woocommerce_url],
                consumer_key: params[:woocommerce_consumer_key],
                consumer_secret: params[:woocommerce_consumer_secret],
                endpoint: endpoint,
                import_type: import_type
              }

              if import_type == 'woocommerce_orders' && params[:woocommerce_order_statuses].present?
                job_args[:order_statuses] = Array(params[:woocommerce_order_statuses]).join(",")
              end

              ::SolidusImporter::WoocommerceImportJob.perform_later(**job_args)

              flash[:success] = t('spree.successfully_created', resource: t('spree.solidus_importer.import'))
              redirect_to admin_solidus_importer_imports_path
            rescue => e
              flash[:error] = e.message
              redirect_back fallback_location: new_admin_solidus_importer_import_path
            end
          else
            super
          end
        end

        def index
          @search = ::SolidusImporter::Import.ransack(params[:q])
          @imports = @search.result(distinct: true)
            .page(params[:page])
            .per(params[:per_page] || Spree::Config[:orders_per_page])
            .order(id: :desc)
        end

        def show
          @import = ::SolidusImporter::Import.find(params[:id])
          @search = @import.rows.ransack(params[:q])
          @import_rows = @search.result(distinct: true).page(params[:page]).per(params[:per_page]).order(id: :desc)
        end

        private

        def import!
          ::SolidusImporter::ImportJob.perform_later(@import.id)
        end

        def model_class
          ::SolidusImporter::Import
        end

        def permitted_resource_params
          params.require(:solidus_importer_import).permit(:file, :import_type)
        end

        def assigns_import_types
          @import_types = ::SolidusImporter::Config.available_types
        end
      end
    end
  end
end
