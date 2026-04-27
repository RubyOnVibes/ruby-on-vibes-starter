# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CurrentRequestHelpers, type: :model do
  # Test the concern's methods by creating a test class that includes it
  let(:test_class) do
    Class.new do
      include CurrentRequestHelpers

      attr_accessor :current_user, :params, :session, :request

      def initialize
        @params = {}
        @session = {}
        @request = OpenStruct.new(uuid: 'test-uuid', ip: '127.0.0.1', user_agent: 'TestAgent')
      end

      def user_signed_in?
        current_user.present?
      end
    end
  end

  let(:helper) { test_class.new }
  let(:alice) { users(:alice) }
  let(:team_workspace) { workspaces(:team_org) }
  let(:personal_workspace) { workspaces(:alice_personal) }

  before { Current.reset }
  after { Current.reset }

  describe '#current_workspace' do
    it 'returns Current.workspace' do
      Current.workspace = team_workspace
      expect(helper.current_workspace).to eq(team_workspace)
    end
  end

  describe '#current_member' do
    it 'returns Current.member' do
      Current.user = alice
      Current.workspace = team_workspace
      expect(helper.current_member).to eq(members(:alice_team_member))
    end
  end

  describe '#setup_current' do
    context 'when user is signed in' do
      before do
        helper.current_user = alice
      end

      it 'sets Current.user' do
        helper.setup_current
        expect(Current.user).to eq(alice)
      end

      it 'sets request metadata' do
        helper.setup_current
        expect(Current.request_id).to eq('test-uuid')
        expect(Current.ip_address).to eq('127.0.0.1')
        expect(Current.user_agent).to eq('TestAgent')
      end
    end
  end

  describe 'workspace resolution' do
    before do
      helper.current_user = alice
    end

    describe '#resolve_workspace_from_params' do
      it 'returns workspace when workspace_id in params' do
        helper.params = { workspace_id: team_workspace.id }
        result = helper.resolve_workspace_from_params
        expect(result).to eq(team_workspace)
      end

      it 'returns nil when workspace_id not in params' do
        helper.params = {}
        result = helper.resolve_workspace_from_params
        expect(result).to be_nil
      end

      it 'returns nil when workspace does not belong to user' do
        helper.params = { workspace_id: workspaces(:bob_personal).id }
        result = helper.resolve_workspace_from_params
        expect(result).to be_nil
      end
    end

    describe '#resolve_workspace_from_session' do
      it 'returns workspace when workspace_id in session' do
        helper.session = { workspace_id: team_workspace.id }
        result = helper.resolve_workspace_from_session
        expect(result).to eq(team_workspace)
      end

      it 'returns nil when workspace_id not in session' do
        helper.session = {}
        result = helper.resolve_workspace_from_session
        expect(result).to be_nil
      end
    end

    describe '#default_workspace' do
      it 'returns personal workspace as fallback' do
        result = helper.default_workspace
        expect(result).to eq(personal_workspace)
      end

      it 'returns existing personal workspace' do
        # User already has a personal workspace (created via after_create callback)
        result = helper.default_workspace
        expect(result).to eq(personal_workspace)
        expect(result.personal?).to be true
      end
    end
  end

  describe 'workspace resolution priority' do
    before do
      helper.current_user = alice
    end

    it 'prefers params over session' do
      helper.params = { workspace_id: team_workspace.id }
      helper.session = { workspace_id: personal_workspace.id }

      workspace = helper.resolve_workspace
      expect(workspace).to eq(team_workspace)
    end

    it 'falls back to session when params empty' do
      helper.params = {}
      helper.session = { workspace_id: team_workspace.id }

      workspace = helper.resolve_workspace
      expect(workspace).to eq(team_workspace)
    end

    it 'falls back to default when both empty' do
      helper.params = {}
      helper.session = {}

      workspace = helper.resolve_workspace
      expect(workspace).to eq(personal_workspace)
    end
  end
end
