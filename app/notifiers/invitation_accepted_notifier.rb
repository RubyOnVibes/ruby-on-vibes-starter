class InvitationAcceptedNotifier < ApplicationNotifier
  # deliver_by :action_cable do |config|
  #   config.channel = "NotificationsChannel"
  #   config.stream = -> { recipient }
  #   config.message = -> {
  #     {
  #       type: 'new_notification',
  #       notification: {
  #         id: record.id,
  #         type: self.class.name,
  #         message: message,
  #         title: title,
  #         url: url,
  #         createdAt: record.created_at.iso8601
  #       }
  #     }
  #   }
  # end

  notification_methods do
    def message
      "#{user_name} accepted your invitation to #{workspace_name}"
    end
    
    def title
      "Invitation Accepted"
    end

    def icon
      "🎉"
    end

    def url
      return workspaces_path unless params[:workspace]
      
      workspace_members_path(params[:workspace])
    end
    
    private
    
    def user_name
      params[:user_name] || params[:record]&.name || "Someone"
    end
    
    def workspace_name
      params[:workspace_name] || params[:workspace]&.name || "a workspace"
    end
  end
end