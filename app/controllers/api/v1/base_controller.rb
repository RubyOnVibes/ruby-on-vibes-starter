class Api::V1::BaseController < ::ActionController::API
  impersonates :user

  include ActionController::Caching
  include Pagy::Method
  include Turbo::Native::Navigation

  include CurrentRequestHelpers
  
  after_action :set_vibes_request_id
  
  private
  
  def set_vibes_request_id
    response.set_header('X-Vibes-Request-ID', request.uuid) if request.uuid
  end
end

