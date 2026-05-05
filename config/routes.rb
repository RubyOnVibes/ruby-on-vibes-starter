Rails.application.routes.draw do
  resources :models, only: [:index, :show] do
    collection do
      post :refresh
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  
  # Devise authentication and admin routes via config/routes/authentication.rb
  draw :authentication
  # Pay related routes in config/routes/payments.rb
  draw :payments
  # Workspaces/Members and multitenancy related routes in config/routes/multitenancy.rb
  draw :multitenancy

  namespace :profile do
    resource :password, only: [:show, :edit, :update]
    resource :registration, only: [:edit, :update]
    resources :referrals, only: [:index] if defined? Refer
  end

  # Notifications routes
  resources :notifications, only: [:index] do
    collection do
      post :mark_all_as_read
    end
    
    member do
      post :mark_as_read
    end
  end
  
  # Chat routes (dual format: ERB/Islands + Inertia)
  resources :chats, except: :edit do
    member do
      post :leave
      post :clear
      get :messages
    end
    
    resources :messages, only: [:create]
    resources :members, only: [:index, :destroy], controller: 'chats/members'
  end
  
  resources :messages, only: [:create]
  
  # Chat invitations
  scope path: 'chats' do
    resources :invitations, only: [:show, :create, :destroy], controller: 'chat_invitations', as: :chat_invitations do
    member do
      post :accept
      post :ignore
      end
    end
  end
  
  # ChatRun cancellation and task continuation
  resources :chat_runs, only: [] do
    member do
      post :cancel
      post :continue
    end
  end

  # Agent tasks - workspace-level index + show
  resources :agent_tasks, only: [:index, :show]
  
  namespace :api do
    namespace :v1 do
      # Mentionable search for @mentions in chat
      resources :mentionables, only: [:index]
      
      # Member lookup for chat invitations
      resources :members, only: [] do
        member do
          get :preview
        end
      end
      
      # Chat-related API
      resources :chats, only: [] do
        member do
          get :pending_invitations
        end
      end
      
      # Agent task polling and management
      resources :agent_tasks, only: [:index, :show] do
        collection do
          post :dismiss
        end
        member do
          post :cancel
        end
      end

      # Webhook endpoint for persistent agents (unauthenticated — token is the auth)
      post "hooks/:token", to: "webhooks#receive", as: :webhook_receive

      # Custom app api (v1) routes go here
    end
  end
  
  # Standard pages (privacy, terms) - always available, AI can customize content
  get "privacy", to: "pages#privacy", as: :privacy
  get "terms", to: "pages#terms", as: :terms

  # ERB homepage - fast, reliable, no build step required
  # For interactive dashboards, use Inertia/React at /dashboard
  root to: "pages#index"

  # Inertia/React dashboard - for complex interactive features
  get "dashboard", to: "inertia_pages#dashboard"

  # Non-app-specific routes
  get "up" => "rails/health#show", as: :rails_health_check
  draw :vibes_api if ENV['VIBES_API_ENABLED'] == 'true'
  
  # Mailbin email viewer (production email testing when using mounted vibes)
  mount Mailbin::Engine => :mailbin if Rails.env.development? || RubyOnVibes.mailbin?
end
