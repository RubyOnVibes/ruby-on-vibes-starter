# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Workspaces", type: :request do
  let(:alice) { users(:alice) }
  let(:bob) { users(:bob) }
  let(:team_workspace) { workspaces(:team_org) }
  let(:personal_workspace) { workspaces(:alice_personal) }

  describe "GET /workspaces" do
    context "when not signed in" do
      it "redirects to sign in" do
        get workspaces_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in" do
      before { sign_in alice }

      it "returns success" do
        get workspaces_path
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /workspaces/:id" do
    context "when signed in as member" do
      before { sign_in alice }

      it "returns success for own workspace" do
        get workspace_path(team_workspace)
        expect(response).to have_http_status(:success)
      end

      it "redirects for workspace user is not member of" do
        get workspace_path(workspaces(:bob_personal))
        expect(response).to redirect_to(workspaces_path)
      end
    end
  end

  describe "GET /workspaces/:id/edit" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "returns success" do
        get edit_workspace_path(team_workspace)
        expect(response).to have_http_status(:success)
      end
    end

    context "when signed in as non-admin member" do
      before do
        members(:bob_team_member).update!(admin: false)
        sign_in bob
      end

      it "redirects with alert" do
        get edit_workspace_path(team_workspace)
        expect(response).to redirect_to(team_workspace)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "PATCH /workspaces/:id" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "updates workspace" do
        patch workspace_path(team_workspace), params: { workspace: { name: "New Name" } }
        expect(team_workspace.reload.name).to eq("New Name")
        expect(response).to redirect_to(team_workspace)
      end

      it "renders edit on invalid params" do
        patch workspace_path(team_workspace), params: { workspace: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as non-admin" do
      before do
        members(:bob_team_member).update!(admin: false)
        sign_in bob
      end

      it "redirects without updating" do
        patch workspace_path(team_workspace), params: { workspace: { name: "Hacked" } }
        expect(team_workspace.reload.name).not_to eq("Hacked")
        expect(response).to redirect_to(team_workspace)
      end
    end
  end

  describe "DELETE /workspaces/:id" do
    context "when signed in as admin" do
      before { sign_in alice }

      it "deletes team workspace" do
        new_workspace = Workspace.create!(
          name: "Deletable Workspace",
          owner: alice,
          is_team_workspace: true
        )

        expect {
          delete workspace_path(new_workspace)
        }.to change { Workspace.count }.by(-1)
        expect(response).to redirect_to(workspaces_path)
      end

      it "prevents deletion of personal workspace" do
        expect {
          delete workspace_path(personal_workspace)
        }.not_to change { Workspace.count }
        expect(response).to redirect_to(personal_workspace)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "PATCH /workspaces/:id/start_session" do
    before { sign_in alice }

    it "sets workspace in session and redirects" do
      patch start_session_workspace_path(team_workspace)
      expect(session[:workspace_id]).to eq(team_workspace.id)
      expect(response).to redirect_to(workspaces_path)
    end

    it "redirects to return_to if provided" do
      patch start_session_workspace_path(team_workspace), params: { return_to: workspaces_path }
      expect(response).to redirect_to(workspaces_path)
    end
  end
end
