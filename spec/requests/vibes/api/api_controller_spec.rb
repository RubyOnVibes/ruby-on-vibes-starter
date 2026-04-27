# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Vibes::Api::ApiController", type: :request do
  # Routes are opt-in; force-draw for tests
  before(:all) do
    @original_vibes_api_enabled = ENV['VIBES_API_ENABLED']
    ENV['VIBES_API_ENABLED'] = 'true'
    Rails.application.reload_routes!
  end

  after(:all) do
    ENV['VIBES_API_ENABLED'] = @original_vibes_api_enabled
    Rails.application.reload_routes!
  end

  let(:valid_token) { 'test-vibes-token-abc123' }
  let(:auth_headers) { { 'X-Vibes-Token' => valid_token } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with('VIBES_API_TOKEN').and_return(valid_token)
  end

  # ── Auth (BaseController) ──────────────────────────────────────────

  describe "authentication" do
    it "returns 401 without a token" do
      post vibes_api_reload_path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq({ 'error' => 'Unauthorized' })
    end

    it "returns 401 with wrong token" do
      post vibes_api_reload_path, headers: { 'X-Vibes-Token' => 'wrong-token' }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when VIBES_API_TOKEN is not configured (fail-closed)" do
      allow(ENV).to receive(:[]).with('VIBES_API_TOKEN').and_return(nil)
      post vibes_api_reload_path, headers: { 'X-Vibes-Token' => 'anything' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── Health ─────────────────────────────────────────────────────────

  describe "GET /vibes/api/health" do
    it "skips auth and returns simple ok when USE_MOUNTED_VIBES is not set" do
      allow(ENV).to receive(:[]).with('USE_MOUNTED_VIBES').and_return(nil)

      get vibes_api_health_path
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ 'status' => 'ok' })
    end

    context "when USE_MOUNTED_VIBES=true" do
      before do
        allow(ENV).to receive(:[]).with('USE_MOUNTED_VIBES').and_return('true')
      end

      it "returns full health payload" do
        # Stub database checks
        allow(ActiveRecord::Base).to receive(:with_connection).and_yield(
          double(select_value: "1", schema_cache: double(clear!: true))
        )
        allow(SolidCache::Record).to receive(:with_connection).and_yield(double(select_value: "1")) if defined?(SolidCache::Record)
        allow(SolidQueue::Record).to receive(:with_connection).and_yield(double(select_value: "1")) if defined?(SolidQueue::Record)

        # Stub filesystem/git checks
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(Pathname.new('/mnt/data/code/.git')).and_return(true)
        allow(Dir).to receive(:exist?).with('/mnt/data/code/.git').and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/mnt/data/bundle/.ready').and_return(true)
        allow(File).to receive(:exist?).with(Pathname.new('/mnt/data/code/fly.toml')).and_return(false)

        allow_any_instance_of(Vibes::Api::ApiController).to receive(:`).and_return("abc123\n")
        allow_any_instance_of(Vibes::Api::ApiController).to receive(:code_repo_state).and_return('clean')
        allow_any_instance_of(Vibes::Api::ApiController).to receive(:code_repo_safe).and_return(true)

        allow(ENV).to receive(:[]).with('BUNDLE_PATH').and_return('/mnt/data/bundle')
        allow(ENV).to receive(:[]).with('GEM_HOME').and_return('/mnt/data/bundle/ruby/3.3.0')

        get vibes_api_health_path

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['status']).to eq('ok')
        expect(body).to have_key('database')
        expect(body).to have_key('bundle')
        expect(body).to have_key('code_repo')
      end

      it "returns 503 when health check raises unexpectedly" do
        # Force an error in the outer begin/rescue (e.g., commit hash retrieval blows up)
        allow_any_instance_of(Vibes::Api::ApiController).to receive(:get_local_commit_hash_from_repo)
          .and_raise(RuntimeError, "disk read error")

        get vibes_api_health_path

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body['status']).to eq('error')
        expect(response.parsed_body['error']).to eq('disk read error')
      end
    end
  end

  # ── Reload ─────────────────────────────────────────────────────────

  describe "POST /vibes/api/reload" do
    it "returns success with valid token" do
      # Stub all reload internals
      allow(RubyOnVibes).to receive(:reload!).and_return(true) if defined?(RubyOnVibes)
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:clear_rails_template_resolver_caches!)
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:reset_vite_and_inertia_rails!)
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:reset_schema_and_routes_and_reload!)
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:restart_ssr_if_needed)

      post vibes_api_reload_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to eq(true)
    end

    it "calls the reload chain" do
      expect_any_instance_of(Vibes::Api::ApiController).to receive(:reload_vibes_config!)
      expect_any_instance_of(Vibes::Api::ApiController).to receive(:clear_rails_template_resolver_caches!)
      expect_any_instance_of(Vibes::Api::ApiController).to receive(:reset_vite_and_inertia_rails!)
      expect_any_instance_of(Vibes::Api::ApiController).to receive(:reset_schema_and_routes_and_reload!)
      expect_any_instance_of(Vibes::Api::ApiController).to receive(:restart_ssr_if_needed)

      post vibes_api_reload_path, headers: auth_headers
    end
  end

  # ── Git Pull ───────────────────────────────────────────────────────

  describe "POST /vibes/api/git_pull" do
    it "returns success on happy path" do
      code_repo = '/mnt/data/code'

      allow(Dir).to receive(:exist?).and_call_original
      allow(Dir).to receive(:exist?).with(File.join(code_repo, '.git')).and_return(true)
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with('/mnt/data/code/REVISION', anything)

      # Stub backtick calls — run a real command that sets $? to success
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:`) { `true`; "abc123\n" }

      post vibes_api_git_pull_path, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to eq(true)
      expect(body).to have_key('commit_hash')
    end

    it "returns 500 when .git directory is missing" do
      allow(Dir).to receive(:exist?).and_call_original
      allow(Dir).to receive(:exist?).with(File.join('/mnt/data/code', '.git')).and_return(false)

      post vibes_api_git_pull_path, headers: auth_headers

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']).to include('Code repo not initialized')
    end

    it "returns 500 when git sync fails" do
      code_repo = '/mnt/data/code'

      allow(Dir).to receive(:exist?).and_call_original
      allow(Dir).to receive(:exist?).with(File.join(code_repo, '.git')).and_return(true)

      # Stub backtick calls — run a real command that sets $? to failure
      allow_any_instance_of(Vibes::Api::ApiController).to receive(:`) { `false`; "some output\n" }

      post vibes_api_git_pull_path, headers: auth_headers

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']).to include('Git sync failed')
    end
  end
end
