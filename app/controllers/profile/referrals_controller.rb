module Profile
  class ReferralsController < ApplicationController
    before_action :authenticate_user!
  end
end
