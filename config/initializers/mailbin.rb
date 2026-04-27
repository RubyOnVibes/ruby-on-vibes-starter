# Mailbin configuration for email capture in production
# 
# When using mounted Vibes (Fly.io), emails are captured to persistent volume
# instead of being sent via external provider. This allows testing email flows efficiently.

if defined?(Mailbin) && ENV['USE_MOUNTED_VIBES'] == 'true'
  Mailbin.storage_location = "/mnt/data/mailbin"
end