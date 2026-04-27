class WorkspaceResource < Madmin::Resource
  menu parent: "Workspaces & Members", position: 2

  attribute :id, form: false
  attribute :name
  attribute :created_at, form: false
  attribute :updated_at, form: false

  attribute :members
  attribute :users
end
