# Prevent madmin from crashing during boot when database isn't ready yet
# This allows Rails to boot quickly without waiting for background DB setup
#
# Madmin will:
# - Boot successfully even if database/tables don't exist
# - Default to :string type for attributes when DB unavailable
# - Automatically work correctly once database is ready
# - No performance impact after initial boot

module Madmin
  class Resource
    class << self
      # Wrap infer_type to handle missing database/tables gracefully
      alias_method :original_infer_type, :infer_type
      
      def infer_type(name)
        # Check if database exists by looking for actual database file (not marker)
        db_not_ready = if ENV['USE_MOUNTED_VIBES'] == 'true'
          !File.exist?("/mnt/data/sqlite/production.sqlite3")
        elsif ENV['RENDER_DISK_PATH']
          !File.exist?("#{ENV['RENDER_DISK_PATH']}/sqlite/production.sqlite3")
        else
          false  # Assume database exists or will be created
        end
        
        if db_not_ready
          :string # Allow madmin to boot even if database isn't ready
        else
          original_infer_type(name)
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
        # Database or table doesn't exist yet - use safe fallback
        # This allows boot during preDeployCommand before databases are created
        Rails.logger.debug "[Madmin] Database not ready for #{name}: #{e.class}"
        :string
      end
    end
  end
end