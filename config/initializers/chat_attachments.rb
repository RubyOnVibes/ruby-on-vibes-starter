# frozen_string_literal: true

##
# Chat Attachment Configuration
#
# Controls what file types and sizes are allowed in chat attachments.
# Used by ReadAttachmentTool and frontend validation.
#
# To customize:
# 1. Edit SUPPORTED_TYPES to add/remove file types
# 2. Edit MAX_FILE_SIZE to change size limits per category
# 3. Restart server for changes to take effect
#
module ChatAttachments
  # Supported file types by category
  # Add/remove MIME types as needed for your use case
  SUPPORTED_TYPES = {
    # Images - Vision models (GPT-4V, Claude 3, Gemini) can analyze these
    images: %w[
      image/png
      image/jpeg
      image/jpg
      image/gif
      image/webp
    ].freeze,
    
    # Text files - LLMs can read and analyze these
    text: %w[
      text/plain
      text/markdown
      text/csv
      application/json
    ].freeze,
    
    # Code files - Useful for code review, debugging, etc.
    code: %w[
      text/x-ruby
      text/x-python
      text/x-javascript
      text/x-typescript
      text/html
      text/css
      application/javascript
      application/typescript
    ].freeze
    
    # Future: Add PDF, audio, video support
    # pdfs: %w[application/pdf].freeze,
    # audio: %w[audio/mpeg audio/wav audio/ogg].freeze,
    # video: %w[video/mp4 video/webm].freeze
  }.freeze
  
  # Maximum file size per category (in bytes)
  # Adjust based on your infrastructure and API limits
  MAX_FILE_SIZE = {
    images: 20.megabytes,  # Vision models can handle large images
    text: 1.megabyte,      # Text files should be small (token limits)
    code: 1.megabyte,      # Code files should be small (token limits)
    # pdfs: 10.megabytes,
    # audio: 25.megabytes,
    # video: 100.megabytes
  }.freeze
  
  # Get all supported MIME types (flattened)
  def self.all_supported_types
    @all_supported_types ||= SUPPORTED_TYPES.values.flatten.freeze
  end
  
  # Check if a content type is supported
  def self.supported?(content_type)
    all_supported_types.include?(content_type)
  end
  
  # Get category for a content type
  def self.category_for(content_type)
    SUPPORTED_TYPES.find { |_category, types| types.include?(content_type) }&.first
  end
  
  # Get max size for a content type
  def self.max_size_for(content_type)
    category = category_for(content_type)
    category ? MAX_FILE_SIZE[category] : 0
  end
  
  # Check if file size is within limits
  def self.within_size_limit?(content_type, byte_size)
    max_size = max_size_for(content_type)
    return false if max_size.zero?
    byte_size <= max_size
  end
  
  # Validate a blob (returns error message or nil if valid)
  def self.validate_blob(blob)
    return "File type not supported" unless supported?(blob.content_type)
    return "File too large" unless within_size_limit?(blob.content_type, blob.byte_size)
    nil
  end
  
  # Human-readable file size
  def self.human_size(bytes)
    return "0 B" if bytes.zero?
    
    units = %w[B KB MB GB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min
    
    "%.1f %s" % [bytes.to_f / 1024**exp, units[exp]]
  end
end

