class Authentication::PasswordsController < Devise::PasswordsController
  include Authentication::Concerns::RegistrationHelpers
end