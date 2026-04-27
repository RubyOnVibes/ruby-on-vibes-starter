class InvitationNotifier < ApplicationNotifier
  deliver_by :email do |config|
    config.mailer = "InvitationsMailer"
    config.method = :invite_email
  end
  
  notification_methods do
    def message
      "#{originator_name} invited you to join #{workspace_name}"
    end
    
    def title
      "You've been invited"
    end
    
    def icon
      "✉️"
    end
    
    def url
      inv = params[:invitation]
      return workspaces_path unless inv
      
      Rails.application.routes.url_helpers.invitation_path(inv)
    end
    
    private
    
    def originator_name
      params[:originator_name] || params[:invitation]&.originator&.name || "Someone"
    end
    
    def workspace_name
      params[:workspace_name] || params[:invitation]&.workspace&.name || "a workspace"
    end
  end
end
