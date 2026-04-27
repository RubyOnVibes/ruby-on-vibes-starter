# frozen_string_literal: true

module Api
  module V1
    ##
    # MentionablesController - Search for @mentionable records
    #
    # Provides autocomplete search across mentionable models for chat @mentions.
    # Each model has explicit search logic here - no magic DSL, easy to customize.
    #
    # GET /api/v1/mentionables?q=search_term
    # GET /api/v1/mentionables?q=search_term&chat_id=chat_xxx
    # GET /api/v1/mentionables?q=search_term&types=Member,Workspace
    #
    # == Adding a New Mentionable Model
    #
    # 1. Include Mentionable in your model:
    #
    #      class Project < ApplicationRecord
    #        include Mentionable
    #      end
    #
    # 2. Add a searcher method below:
    #
    #      def search_projects(query)
    #        scope = current_workspace.projects
    #        search_records(scope, :name, query)
    #      end
    #
    # 3. Register it in SEARCHERS:
    #
    #      SEARCHERS = {
    #        ...
    #        'Project' => :search_projects
    #      }.freeze
    #
    class MentionablesController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :set_search_params

      ##
      # Model name => searcher method mapping
      #
      # Add your app-specific mentionable models here.
      # Method must return Array of mention hashes (use record.to_mention).
      #
      SEARCHERS = {
        'Member' => :search_members,
        'Workspace' => :search_workspaces
        # 'Chat' => :search_chats  # Uncomment to enable chat mentions
      }.freeze

      # GET /api/v1/mentionables
      def index
        return render json: { results: [] } if @query.blank?

        results = @types.flat_map { |type| search_type(type) }

        render json: { results: results }
      end

      private

      def set_search_params
        @query = params[:q].to_s.strip
        @limit = parse_limit(params[:limit])
        @chat = find_chat(params[:chat_id])
        @types = parse_types(params[:types])
      end

      def parse_limit(limit_param)
        return 5 if limit_param.blank?

        [[limit_param.to_i, 1].max, 10].min
      end

      def parse_types(types_param)
        if types_param.present?
          requested = types_param.to_s.split(',').map(&:strip).map(&:classify)
          SEARCHERS.keys & requested
        else
          SEARCHERS.keys
        end
      end

      def find_chat(chat_id)
        return nil if chat_id.blank?

        current_member.chats.find_by(id: chat_id) ||
          current_member.chats.find_by_prefix_id(chat_id)
      end

      def search_type(type)
        method_name = SEARCHERS[type]
        return [] unless method_name && respond_to?(method_name, true)

        send(method_name, @query)
      rescue StandardError => e
        Rails.logger.error "[MentionablesController] Search failed for #{type}: #{e.message}"
        []
      end

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # Search Helper
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      ##
      # Standard search pattern for single-column LIKE search
      #
      # @param scope [ActiveRecord::Relation] Pre-scoped relation
      # @param column [Symbol] Column to search (e.g., :name)
      # @param query [String] Search query
      # @param order [Symbol] Column to order by (default: same as search column)
      # @return [Array<Hash>] Mention hashes
      #
      def search_records(scope, column, query, order: nil)
        table = scope.klass.arel_table

        scope
          .where(table[column].lower.matches("%#{query.downcase}%"))
          .order(order || column)
          .limit(@limit)
          .map(&:to_mention)
      end

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # Searchers
      #
      # Each method:
      #   1. Determines the security scope (who can the user see?)
      #   2. Applies the search filter
      #   3. Returns array of mention hashes via .to_mention
      #
      # The @chat context expands scope for group chats (cross-workspace).
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      ##
      # Search members
      #
      # Scope:
      #   - With chat: Members in that chat (may span workspaces)
      #   - Without chat: No results (requires context)
      #
      def search_members(query)
        return [] unless @chat

        @chat.members
          .eager_load(:user)
          .where(
            "LOWER(users.first_name) LIKE :q OR LOWER(users.last_name) LIKE :q OR LOWER(users.email) LIKE :q",
            q: "%#{query.downcase}%"
          )
          .order("users.first_name")
          .limit(@limit)
          .map(&:to_mention)
      end

      ##
      # Search workspaces
      #
      # Scope:
      #   - With chat: Workspaces of chat members (cross-workspace visibility)
      #   - Without chat: Current workspace only
      #
      def search_workspaces(query)
        scope = if @chat
          Workspace.where(id: @chat.members.select(:workspace_id))
        else
          Workspace.where(id: Current.workspace&.id)
        end

        search_records(scope, :name, query)
      end

      ##
      # Search chats (disabled by default)
      #
      # Scope: User's accessible chats
      #
      # To enable: Add 'Chat' => :search_chats to SEARCHERS
      #
      # Security note: Chat mentions can leak information about what
      # chats exist. Consider your threat model before enabling.
      #
      def search_chats(query)
        scope = current_member.chats
        search_records(scope, :name, query, order: { updated_at: :desc })
      end

      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      # Add your app-specific searchers below
      # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      # Example: Search projects
      #
      # def search_projects(query)
      #   scope = current_workspace.projects
      #   search_records(scope, :name, query)
      # end
    end
  end
end
