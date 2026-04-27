class InertiaPagesController < ApplicationController
  # This controller serves Inertia/React pages for complex interactive features
  layout "inertia"

  # Dashboard requires authentication - it's the interactive part of the app
  def dashboard
    ahoy.track "Ran action", request.path_parameters if ENV['AHOY_TRACKING_ENABLED'] == 'true'

    render inertia: 'DashboardPage', props: {
      user: current_user ? {
        id: current_user.id,
        email: current_user.email,
        firstName: current_user.first_name,
        lastName: current_user.last_name
      } : nil
    }
  end
end