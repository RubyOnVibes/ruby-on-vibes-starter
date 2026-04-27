# Top-level member show for @mentions: /m/:id
# Access: any authenticated user (limited view for non-workspace members)
class MembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_member

  def show
    authorize @member
    @member_permissions = policy(@member).to_h
  end

  private

  def set_member
    @member = Member.find_by_prefix_id(params[:id])
    return redirect_to root_path, alert: "Member not found" if @member.nil?

    @workspace = @member.workspace
  end
end
