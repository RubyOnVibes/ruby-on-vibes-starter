require 'rails_helper'

RSpec.describe 'Smoke', type: :request do
  it 'serves the Rails health endpoint' do
    get '/up'
    expect(response).to have_http_status(:ok)
  end
end
