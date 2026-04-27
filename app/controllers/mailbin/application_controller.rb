class Mailbin::ApplicationController < ::ApplicationController
  before_action :authenticate_mailbin_user!

  private

  def authenticate_mailbin_user!
    raise 'Mailbin not allowed in this environment' unless Rails.env.development? || ENV['USE_MOUNTED_VIBES'] == 'true'

    redirect_to '/' unless current_user&.admin?
  end
end