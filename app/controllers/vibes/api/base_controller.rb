module Vibes
  module Api
    class BaseController < ::ActionController::API
      before_action :authenticate_vibes_api
      after_action :set_vibes_request_id

      private
      
      def set_vibes_request_id
        response.set_header('X-Vibes-Request-ID', request.uuid) if request.uuid
      end

      def authenticate_vibes_api
        static_token = request.headers['X-Vibes-Token'].to_s
        expected_token = ENV['VIBES_API_TOKEN'].to_s

        # Fail closed: a missing server-side token must NEVER let requests through.
        if expected_token.blank?
          Rails.logger.error "❌ Vibes API token not configured"
          render json: { error: 'Unauthorized' }, status: 401 and return
        end

        unless ActiveSupport::SecurityUtils.secure_compare(static_token, expected_token)
          Rails.logger.error "❌ Vibes API token mismatch"
          render json: { error: 'Unauthorized' }, status: 401 and return
        end
      end
    end
  end
end