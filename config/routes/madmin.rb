# Below are the routes for madmin
namespace :madmin, path: :admin do
  resources :workspaces
  resources :members
  resources :connected_accounts
  resources :plans
  resources :users do
    resource :sessions, module: :user
  end
  resources :models
  post "refresh_models", to: "application#refresh_models", as: :admin_refresh_models
  namespace :refer do
    resources :referrals
  end
  namespace :refer do
    resources :referral_codes
  end
  namespace :refer do
    resources :visits
  end
  namespace :pay do
    resources :charges
  end
  namespace :pay do
    resources :customers
  end
  namespace :active_storage do
    resources :attachments
  end
  namespace :active_storage do
    resources :blobs
  end
  namespace :active_storage do
    resources :variant_records
  end
  namespace :pay do
    resources :merchants
  end
  namespace :pay do
    resources :payment_methods
  end
  namespace :pay do
    resources :subscriptions
  end
  namespace :action_text do
    resources :rich_texts
  end
  namespace :action_text do
    resources :encrypted_rich_texts
  end
  namespace :noticed do
    resources :events
  end
  namespace :noticed do
    resources :notifications
  end
  root to: "dashboard#show"
end
