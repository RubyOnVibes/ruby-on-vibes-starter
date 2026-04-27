class MemberResource < Madmin::Resource
  menu parent: "Workspaces & Members", position: 1

  attribute :id, form: false
  attribute :created_at, form: false
  attribute :updated_at, form: false

  attribute :workspace, index: true
  attribute :member
end
