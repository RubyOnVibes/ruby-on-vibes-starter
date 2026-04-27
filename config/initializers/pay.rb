require_relative "../../lib/pay_subscription_patch"
require_relative "../../lib/pay_charge_patch"

Pay.setup do |config|
  config.routes_path = "/"

  config.mail_to = -> {
    recipients = []

    if workspace = params[:pay_customer].owner
      recipients << ActionMailer::Base.email_address_with_name(
        workspace.owner.email,
        params[:pay_customer].customer_name
      )
      recipients << workspace.billing_email if workspace.billing_email?
    end

    recipients
  }
end

Rails.configuration.to_prepare do
  # Called at boot and on every code reload (development auto-reload + hot reload)
  RubyOnVibes.sync_pay_config! if defined?(RubyOnVibes)
  
  Receipts.default_font = {
    bold: Rails.root.join("app/assets/fonts/Inter-Bold.ttf"),
    normal: Rails.root.join("app/assets/fonts/Inter-Regular.ttf")
  }

  Pay::Charge.include PayChargePatch
  Pay::Subscription.include PaySubscriptionPatch
end