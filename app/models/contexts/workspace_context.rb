# frozen_string_literal: true

##
# WorkspaceContext - Structured LLM context for Workspace records
#
# Provides schema-driven serialization for workspaces when mentioned
# or used in chat context. Ensures consistent structure for LLM understanding.
#
class WorkspaceContext < RecordContext
  schema do
    description "A workspace where users collaborate"

    string :id, description: "Workspace ID (org_xxx)"
    string :name, description: "Workspace display name"
    string :path, description: "CLICKABLE PATH - use this for markdown links to this workspace"

    string :type,
      description: "Type - personal (single member) or team (multi-member)",
      enum: ['personal', 'team']

    integer :members_count,
      description: "Number of members in the workspace",
      minimum: 0

    string :owner_username, description: "Owner's @username"
  end
  
  ##
  # Create context from Workspace record
  #
  # @param workspace [Workspace] The workspace to serialize
  # @return [WorkspaceContext] Context instance
  #
  def self.from_record(workspace)
    new(
      id: workspace.to_param,
      name: workspace.name,
      path: workspace.mentionable_path,
      type: workspace.personal? ? 'personal' : 'team',
      members_count: workspace.members_count || 0,
      owner_username: workspace.owner.username
    )
  end

  def summary
    "#{data[:type].titleize} workspace '#{data[:name]}' (#{data[:members_count]} #{data[:members_count] == 1 ? 'member' : 'members'}, owned by @#{data[:owner_username]})"
  end
end

