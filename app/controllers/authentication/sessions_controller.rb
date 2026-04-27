class Authentication::SessionsController < Devise::SessionsController
  include Authentication::Concerns::RegistrationHelpers
end