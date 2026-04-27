module Authentication::Concerns::RegistrationHelpers
  extend ActiveSupport::Concern

  included do
    helper_method :users_url
  end

  def users_url
    new_user_registration_url
  end
end

