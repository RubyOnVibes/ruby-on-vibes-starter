# frozen_string_literal: true

##
# ChatPolicy - Authorization for chat actions
#
# Permissions:
# - Owner: Can do everything (rename, delete, invite, remove members)
# - Member: Can view, send messages, stop AI runs
# - Non-member: No access
#
class ChatPolicy < ApplicationPolicy
  def show?
    record.member_exists?(member)
  end
  
  def update?
    owner?
  end
  
  def destroy?
    owner?
  end
  
  def manage_members?
    owner?
  end
  
  def send_messages?
    member?
  end
  
  def cancel_runs?
    member?
  end
  
  def leave?
    member? && !owner?
  end
  
  def to_h
    {
      "can_view" => show?,
      "can_rename" => update?,
      "can_delete" => destroy?,
      "can_manage_members" => manage_members?,
      "can_send_messages" => send_messages?,
      "can_cancel_runs" => cancel_runs?,
      "can_leave" => leave?,
      "is_owner" => owner?,
      "is_member" => member?
    }
  end
  
  private
  
  def owner?
    return false unless member
    record.owner?(member)
  end
  
  def member?
    return false unless member
    record.member_exists?(member)
  end
end
