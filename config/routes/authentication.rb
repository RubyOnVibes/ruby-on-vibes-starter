devise_for :users, controllers: {
  registrations: "authentication/registrations",
  sessions: "authentication/sessions",
  passwords: "authentication/passwords",
  unlocks: "authentication/unlocks"
}

authenticated :user, lambda { |u| u.admin? } do
  draw :madmin
  mount Blazer::Engine, at: "admin/queries"
  mount MissionControl::Jobs::Engine, at: "admin/mission-control"
end