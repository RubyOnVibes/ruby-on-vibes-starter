# frozen_string_literal: true

module Api
  module V1
    ##
    # MembersController - API for member lookup and preview
    #
    class MembersController < Api::V1::BaseController
      before_action :authenticate_user!
      
      ##
      # GET /api/v1/members/:id/preview
      # Preview member info for chat invitations
      #
      def preview
        member_id = params[:id]
        
        @member = if member_id.to_s.start_with?('mbr_')
          Member.find_by_prefix_id(member_id)
        else
          Member.find_by(id: member_id)
        end
        
        unless @member
          render json: { error: 'Member not found' }, status: :not_found
          return
        end
        
        render json: {
          memberId: @member.to_param,
          userName: @member.user.name,
          orgName: @member.workspace.name,
          orgType: @member.workspace.personal? ? 'Personal' : 'Team'
        }
      end
    end
  end
end
