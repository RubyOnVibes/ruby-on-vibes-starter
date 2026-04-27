# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Workspaces::Members", type: :request do
  let(:alice) { users(:alice) }
  let(:bob) { users(:bob) }
  let(:team_workspace) { workspaces(:team_org) }
  let(:personal_workspace) { workspaces(:alice_personal) }
  let(:bob_member) { members(:bob_team_member) }

  describe "GET /workspaces/:workspace_id/members" do
    before { sign_in alice }

    it "redirects to workspace" do
      get workspace_members_path(team_workspace)
      expect(response).to redirect_to(team_workspace)
    end
  end

  describe "GET /workspaces/:workspace_id/members/:id/edit" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "returns" do
        get edit_workspace_member_path(team_workspace, bob_member)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as non-admin" do
      before do
        members(:bob_team_member).update!(admin: false)
        sign_in bob
      end

      it "redirects with alert" do
        get edit_workspace_member_path(team_workspace, bob_member)
        expect(response).to redirect_to(team_workspace)
      end
    end
  end

  describe "PATCH /workspaces/:workspace_id/members/:id" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "updates member roles" do
        patch workspace_member_path(team_workspace, bob_member), params: { member: { admin: true } }
        expect(bob_member.reload.admin?).to be true
        expect(response).to redirect_to(team_workspace)
      end
    end
  end

  describe "DELETE /workspaces/:workspace_id/members/:id" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "removes member from workspace" do
        # Create a new member without any associated records (chat_members, etc.)
        new_user = User.create!(email: "test@example.com", password: "password123", first_name: "Test")
        new_member = team_workspace.members.create!(user: new_user, roles: { "admin" => false })

        expect {
          delete workspace_member_path(team_workspace, new_member)
        }.to change { team_workspace.members.count }.by(-1)
        expect(response).to redirect_to(team_workspace)
      end

      it "prevents removing workspace owner" do
        owner_member = members(:alice_team_member)
        expect {
          delete workspace_member_path(team_workspace, owner_member)
        }.not_to change { team_workspace.members.count }
        expect(response).to redirect_to(team_workspace)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
