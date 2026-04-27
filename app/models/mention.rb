# frozen_string_literal: true

##
# Mention - References to models mentioned in messages via @mentions
#
# Uses polymorphic association for clean, Rails-standard relationships
# Prefixed ID used for stable, token-efficient references
#
# IMPORTANT: No denormalized label column!
# Label is always fetched fresh from mentionable.mentionable_label
# This ensures mentions stay up-to-date when chat names, usernames, etc. change
#
class Mention < ApplicationRecord
  belongs_to :message
  belongs_to :mentionable, polymorphic: true, optional: true  # Allow nil for deleted records
  
  # Check if the mentioned record has been deleted
  def deleted?
    mentionable.nil?
  end
  
  # Get the routing param for the mentioned model
  # Uses to_param for prefixed IDs, falls back to id
  def mentionable_param
    return nil unless mentionable
    
    mentionable.respond_to?(:to_param) ? mentionable.to_param : mentionable.id.to_s
  end
  
  # Get the current label (always fresh from mentionable)
  def label
    return "[Deleted #{mentionable_type}]" if deleted?
    
    mentionable.mentionable_label
  end
  
  # Serialize for frontend
  def as_json(options = {})
    {
      id: mentionable_param,        # Prefixed ID (chat_xxx)
      model: mentionable_type,
      label: label,                 # Fresh label from mentionable
      path: mentionable&.mentionable_path,  # For navigation
      deleted: deleted?  # Flag for frontend
    }
  end
end
