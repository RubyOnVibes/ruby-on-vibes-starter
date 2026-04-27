resources :invitations, only: [:show, :update, :destroy]

resources :members, only: [:show]

resources :workspaces do
  member do
    patch :start_session
  end

  # Nested member routes for admin actions (workspace admins only)
  resources :members, except: [:show], controller: 'workspaces/members'

  resources :invitations, module: :workspaces do
    member do
      post :resend
    end
  end
end