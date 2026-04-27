class Authentication::UnlocksController < Devise::UnlocksController
  include Authentication::Concerns::RegistrationHelpers
end