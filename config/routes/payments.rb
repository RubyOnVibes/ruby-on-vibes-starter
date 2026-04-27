resource :pricing, to: 'pages#pricing'

namespace :checkout do
  resource :return, only: [:show], controller: '/payments/checkout/returns'
end

resource :checkout, controller: 'payments/checkout'

resource :payments, controller: :payments

namespace :payments do
  resource :info

  resources :charges do
    member { get :invoice }
  end

  resources :subscriptions, only: [:index, :edit, :update] do    
    member do
      get :cancelling
      delete :cancel
      get :pausing
      patch :pause
      get :unpausing
      patch :unpause
      get :upcoming
      get :new_payment_method
    end
  end
end
