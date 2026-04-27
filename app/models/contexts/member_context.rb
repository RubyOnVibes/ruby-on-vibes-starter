# frozen_string_literal: true

##
# MemberContext - Structured LLM context for Member records
#
# Provides schema-driven serialization for workspace members when mentioned
# or used in chat context. Captures user identity within workspace scope.
#
class MemberContext < RecordContext
  schema do
    description "A user's membership in an workspace with roles and permissions"

    string :id, description: "Prefixed member ID (mbr_xxx)"
    string :path, description: "CLICKABLE PATH - use this for markdown links to this member"
    string :name, description: "User's display name"
    string :username, description: "User's @username"

    object :workspace, description: "Workspace this member belongs to" do
      string :id, description: "Workspace ID"
      string :name, description: "Workspace name"
      string :type, enum: ['personal', 'team']
    end

    array :roles,
      of: :string,
      description: "Member's roles in the workspace (e.g., admin, member)"

    boolean :is_owner,
      description: "Whether this member is the workspace owner"
  end

  ##
  # Create context from Member record
  #
  # @param member [Member] The member to serialize
  # @return [MemberContext] Context instance
  #
  def self.from_record(member)
    new(
      id: member.to_param,
      path: member.mentionable_path,
      name: member.user.name,
      username: member.user.username,
      workspace: {
        id: member.workspace.to_param,
        name: member.workspace.name,
        type: member.workspace.personal? ? 'personal' : 'team'
      },
      roles: member.active_roles.map(&:to_s),
      is_owner: member.workspace_owner?
    )
  end
  
  ##
  # Generate human-readable summary
  # Used for inline mentions and logging
  #
  def summary
    name = data[:name]
    org_name = data[:workspace][:name]
    roles_text = data[:roles].join(', ')
    owner_text = data[:is_owner] ? ' (Owner)' : ''

    "#{name} in #{org_name} [#{roles_text}]#{owner_text}"
  end
end

