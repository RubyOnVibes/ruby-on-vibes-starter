# frozen_string_literal: true

##
# Mentionables - Reset cached models on code reload (development only)
#
# Models define their own mentionable search via the DSL in the model itself.
# See: app/models/member.rb, app/models/workspace.rb, etc.
#
Rails.application.config.to_prepare do
  Mentionables.reset! if defined?(Mentionables)
end
