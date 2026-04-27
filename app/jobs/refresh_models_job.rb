class RefreshModelsJob < SolidQueueJob

  def perform
    return unless enabled?
    
    Model.refresh!
  end

  private

  def enabled?
    return false unless RubyOnVibes.llm?

    # Only refresh models for mounted vibes apps AFTER mounted bundle and repo are ready.
    if ENV['USE_MOUNTED_VIBES'] == 'true'
      repo_mounted = File.exist?('/mnt/data/code/app/jobs/refresh_models_job.rb')
      bundle_ready = File.exist?('/mnt/data/bundle/.ready')
      bundle_active = ENV['BUNDLE_PATH'] == '/mnt/data/bundle' && ENV['GEM_HOME'].include?('/mnt/data/bundle')

      repo_mounted && bundle_ready && bundle_active
    else
      true
    end
  end
end