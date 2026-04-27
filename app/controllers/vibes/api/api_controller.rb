# Sync surface for the hosted Ruby on Vibes platform.
# Off by default: only mounts when VIBES_API_ENABLED=true, and auth fails
# closed if VIBES_API_TOKEN is unset (see Vibes::Api::BaseController).
# Self-hosters can delete this entire app/controllers/vibes/ directory and
# the matching routes — nothing else in the template depends on it.
# See docs/vibes-api.md for the full contract.
module Vibes
  module Api
    class ApiController < Vibes::Api::BaseController
      skip_before_action :authenticate_vibes_api, only: :health
      
      def health
        return render json: { status: 'ok' }, status: 200 unless ENV['USE_MOUNTED_VIBES'] == 'true'
        
        begin
          commit = get_local_commit_hash_from_repo || 'unknown'
          
          db_primary_ok = check_database(:primary)
          db_cache_ok = check_database(:cache)
          db_queue_ok = check_database(:queue)
          
          all_databases_ready = db_primary_ok && db_cache_ok && db_queue_ok
          bundle_ready = File.exist?('/mnt/data/bundle/.ready')
          bundle_active = ENV['BUNDLE_PATH'] == '/mnt/data/bundle' && ENV['GEM_HOME'].include?('/mnt/data/bundle')
          
          # Include optional MCP (Model Context Protocol) info if enabled
          health_data = { 
            status: 'ok',
            timestamp: Time.current.iso8601,
            database: all_databases_ready ? 'connected' : 'disconnected',
            databases: {
              primary: db_primary_ok ? 'connected' : 'disconnected',
              cache: db_cache_ok ? 'connected' : 'disconnected',
              queue: db_queue_ok ? 'connected' : 'disconnected',
              all_ready: all_databases_ready
            },
            bundle: {
              ready: bundle_ready,  # ready = files exist on volume
              active: bundle_active # active = app is ACTUALLY running with them (app restarted after hot bundle and code repo prepared)
            },
            image: get_fly_image_from_toml,
            code_repo: {
              state: code_repo_state,
              safe_directory: code_repo_safe,
              commit: commit
            },
            mcp: (Rails.application.config.tidewave&.mcp_info_for_health rescue nil)
          }
          
          render json: health_data
        rescue => e
          Rails.logger.error "❌ Health check failed: #{e.message}"
          render json: { 
            status: 'error',
            error: e.message,
            timestamp: Time.current.iso8601
          }, status: 503
        end
      end

      def reload
        begin
          reload_vibes_config!
          clear_rails_template_resolver_caches!
          reset_vite_and_inertia_rails!
          reset_schema_and_routes_and_reload!

          restart_ssr_if_needed # attempt to end node process running ssr.js & let vibes-server restart it with new bundle

          render json: { 
            success: true, 
            message: "Hot reload completed", 
            timestamp: Time.current.iso8601 
          }
        rescue => e
          Rails.logger.error "❌ Hot reload failed: #{e.message}"

          render json: { success: false, error: e.message }, status: 500
        end
      end

      # POST /vibes/api/git_pull
      # Replicates the exact behavior of the SSH-based git pull script
      # This is the API-first deployment path with SSH as fallback
      def git_pull
        begin
          Rails.logger.info "📥 Git pull and sync triggered via API"
          
          code_repo_path = '/mnt/data/code'
          
          # Step 1: Verify code repo exists (matches SSH script check)
          unless Dir.exist?(File.join(code_repo_path, '.git'))
            Rails.logger.error "❌ Code repo not initialized"
            render json: { success: false, error: "Code repo not initialized" }, status: 500
            return
          end

          # Ensure safe.directory is configured
          `git config --global --add safe.directory /mnt/data/code 2>/dev/null`
          
          # CRITICAL: Ensure code repo is owned by rails user (fixes permission denied on .git/FETCH_HEAD)
          # SSH operations run as root and may create root-owned files in .git/
          # API runs as rails user and needs write access
          # Uses secure wrapper script that only allows /mnt/data/* paths (prevents privilege escalation)
          Rails.logger.info "🔧 Ensuring volume ownership for rails user..."
          chown_output = `sudo /usr/local/bin/fix-vibes-ownership 2>&1`
          unless $?.success?
            Rails.logger.warn "⚠️ Ownership fix failed (non-critical): #{chown_output}"
          end
      
          # Step 2: Get current state (thread-safe with -C flag)
          current_commit = `git -C #{Shellwords.escape(code_repo_path)} rev-parse HEAD 2>/dev/null`.strip
          remote_url = `git -C #{Shellwords.escape(code_repo_path)} remote get-url origin 2>/dev/null`.strip
          
          Rails.logger.info "Current commit: #{current_commit}"
          Rails.logger.info "Remote URL: #{remote_url.gsub(/:.*@/, ':***@')}" # Mask credentials
          
          # Verify remote is configured (matches SSH script check)
          if remote_url.empty?
            Rails.logger.error "❌ Git remote not configured!"
            render json: { success: false, error: "Git remote not configured" }, status: 500
            return
          end
          
          # Step 3: FORCE CLEAN working tree before pulling
          # CRITICAL: Discard ALL local changes (bundle install creates dirty Gemfile.lock, schema dumps modify files)
          # Gitea is source of truth - we don't preserve any local modifications
          begin
            Rails.logger.info "🧹 Force cleaning working tree before pull (discarding ALL local changes)..."

            escaped = Shellwords.escape(code_repo_path)

            # Abort any in-progress git operations (single subprocess to minimize blocking time in Falcon's event loop)
            `git -C #{escaped} rebase --abort 2>/dev/null; git -C #{escaped} merge --abort 2>/dev/null; git -C #{escaped} cherry-pick --abort 2>/dev/null`

            # Discard ALL local changes (tracked files and untracked files)
            reset_output = `git -C #{escaped} reset --hard HEAD 2>&1`
            Rails.logger.debug "Reset output: #{reset_output}" if reset_output.present?

            clean_output = `git -C #{escaped} clean -fd 2>&1`
            Rails.logger.debug "Clean output: #{clean_output}" if clean_output.present?

            # NOTE: git gc removed — it's a heavy maintenance operation that blocks Falcon's
            # fiber event loop for seconds, causing "queue closed" errors when the HTTP
            # connection times out before the response can be sent. Stale refs are harmless
            # for pull operations. Run gc as scheduled maintenance if needed.

            Rails.logger.info "✅ Working tree forcefully cleaned"
          rescue => clean_error
            Rails.logger.warn "⚠️ Force cleanup failed: #{clean_error.message}"
            # Continue anyway - pull might still work
          end

          # Step 4: Force-sync with Gitea (fetch + reset, not pull)
          # Using fetch+reset instead of pull --ff-only because local main can diverge
          # from Gitea if build operations (bundle install, migrations, etc.) leave
          # local commits or dirty merge state. Gitea is source of truth.
          Rails.logger.info "🔄 Fetching from Gitea and resetting to origin/main..."
          escaped_path = Shellwords.escape(code_repo_path)
          pull_output = `git -C #{escaped_path} fetch origin main 2>&1 && git -C #{escaped_path} checkout -f main 2>&1 && git -C #{escaped_path} reset --hard origin/main 2>&1`

          unless $?.success?
            Rails.logger.error "❌ Git sync failed: #{pull_output}"
            render json: { success: false, error: "Git sync failed: #{pull_output}" }, status: 500
            return
          end

          Rails.logger.info "✅ Synced with Gitea"
                                        
          # Step 4: Get final commit hash (thread-safe with -C flag)
          new_commit = `git -C #{Shellwords.escape(code_repo_path)} rev-parse HEAD`.strip
          Rails.logger.info "New commit: #{new_commit}"
          
          # Step 5: Write REVISION file (matches SSH script)
          File.write('/mnt/data/code/REVISION', new_commit)
          
          Rails.logger.info "✅ Git pull and sync completed successfully"
          
          render json: {
            success: true,
            commit_hash: new_commit,
            message: "Git pull and sync completed",
            timestamp: Time.current.iso8601
          }
        rescue => e
          Rails.logger.error "❌ Git pull and sync failed: #{e.message}"
          render json: { success: false, error: e.message }, status: 500
        end
      end

      private

      def reload_vibes_config!
        # reload! handles both loading fresh yml and syncing dependent configs
        RubyOnVibes.reload! if defined?(RubyOnVibes)
      end

      def clear_rails_template_resolver_caches!
        ActionController::Base.view_paths.each { |r| r.clear_cache if r.respond_to?(:clear_cache) }
        ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)
        ActionView::Resolver.caching = false
        ActionView::Resolver.caching = true
        Rails.cache.clear
      end

      def reset_vite_and_inertia_rails!
        if defined?(ViteRuby)
          ViteRuby.instance.manifest.refresh
        end

        if defined?(InertiaRails) && defined?(ViteRuby)
          InertiaRails.configuration.version = ViteRuby.digest
        end
      end

      def reset_schema_and_routes_and_reload!
        # Use with_connection for fiber-safe database access (required for Falcon)
        ActiveRecord::Base.with_connection do |conn|
          conn.schema_cache.clear!
        end
        ActiveRecord::Base.descendants.each do |model|
          model.reset_column_information if model.respond_to?(:reset_column_information)
        end

        Rails.application.routes_reloader.reload!

        # FALCON SAFETY: reloader.reload! unloads autoloaded constants (Zeitwerk) so new
        # code is picked up on the next request. However, it also tears down and rebuilds
        # connection pools, which can race with other Falcon fibers (health checks, SolidQueue
        # polls) sharing the same async event loop. When another fiber is mid-flight, the
        # shared Async::Queue can get closed → ClosedQueueError ("queue closed").
        #
        # This is safe to rescue: the constant unloading (the important part) is pure in-memory
        # work that completes before the I/O-related pool teardown that triggers the error.
        # The next request will lazy-reload the new code successfully.
        begin
          Rails.application.reloader.reload!
        rescue ClosedQueueError => e
          Rails.logger.warn "⚠️ reloader.reload! hit Falcon fiber race condition (non-fatal): #{e.message}"
        end
      end

      def check_database(db_purpose)
        case db_purpose
        when :primary
          # Primary database - fiber-safe connection check
          ActiveRecord::Base.with_connection do |conn|
            conn.select_value("SELECT 1").to_s == "1"
          end
        when :cache
          # SolidCache database connection
          SolidCache::Record.with_connection do |conn|
            conn.select_value("SELECT 1").to_s == "1"
          end
        when :queue
          # SolidQueue database connection
          SolidQueue::Record.with_connection do |conn|
            conn.select_value("SELECT 1").to_s == "1"
          end
        else
          false
        end
      rescue => e
        Rails.logger.debug "DB check failed for #{db_purpose}: #{e.class}: #{e.message}"
        false
      end

      def get_local_commit_hash_from_repo
        code_root = Pathname.new('/mnt/data/code')
        git_dir = code_root.join('.git')
        return nil unless Dir.exist?(git_dir)

        result = `git -C #{Shellwords.escape(code_root.to_s)} rev-parse HEAD 2>/dev/null`.strip
        result.present? && result != 'HEAD' ? result : nil
      rescue => e
        Rails.logger.warn "⚠️ Failed to get code repo commit hash: #{e.message}"
        nil
      end

      def get_fly_image_from_toml
        fly_toml_path = Pathname.new('/mnt/data/code/fly.toml')
        return nil unless File.exist?(fly_toml_path)

        File.readlines(fly_toml_path).each do |line|
          if line =~ /^\s*image\s*=\s*"([^"]+)"/
            return $1.split(':').last
          end
        end

        nil
      rescue => e
        Rails.logger.warn "⚠️ Failed to read fly.toml image: #{e.message}"
        nil
      end

      # Restart SSR server if new bundle exists (hot code update)
      # SSR is a Node.js process with old bundle in memory - must restart to pick up changes
      def restart_ssr_if_needed
        ssr_bundle = '/mnt/data/code/vite/ssr/ssr.js'
        return unless File.exist?(ssr_bundle)
        
        begin
          Rails.logger.info "🔮 Restarting SSR server to load new bundle..."
          pids = `pgrep -f 'node.*ssr\.js'`.strip.split("\n") # Find SSR process (node running ssr.js)
          
          if pids.any?
            pids.each do |pid|
              Rails.logger.info "  Killing SSR process: #{pid}"
              Process.kill('TERM', pid.to_i)
            end
            
            sleep 0.5 # Wait for graceful shutdown
            
            # bin/vibes-server will auto-restart SSR (handled by trap/wait loop)
            Rails.logger.info "✅ SSR process killed, will auto-restart with new bundle"
          else
            Rails.logger.info "⏭️  No SSR process found (may not be enabled)"
          end
        rescue => e
          Rails.logger.warn "⚠️ SSR restart failed (non-critical): #{e.message}"
        end
      end

      def code_repo_state
        if Dir.exist?('/mnt/data/code/.git')
          status = `git -C /mnt/data/code status --porcelain 2>/dev/null`
          status.present? ? 'dirty' : 'clean'
        else
          'missing'
        end
      rescue => e
        'unknown'
      end

      def code_repo_safe
        safe_dirs = `git config --global --get-all safe.directory 2>/dev/null`.to_s.lines.map(&:strip)
        safe_dirs.include?('/mnt/data/code')
      rescue => e
        false
      end
    end
  end
end