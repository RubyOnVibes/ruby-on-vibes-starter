# frozen_string_literal: true

# The application's upload/download boundary. RubyLLM owns storage, read
# digests, conversion caching, and the tools that work with these files.
# Callers must authorize the chat before constructing a library.
class ChatFileLibrary
  class InvalidUpload < StandardError; end

  MAX_UPLOAD_BYTES = 25.megabytes
  MAX_FILENAME_BYTES = 180
  UPLOAD_TYPES = {
    ".pdf" => ["application/pdf"],
    ".txt" => ["text/plain"],
    ".md" => ["text/markdown", "text/plain"],
    ".csv" => ["text/csv", "text/plain"],
    ".json" => ["application/json", "text/plain"],
    ".png" => ["image/png"],
    ".jpg" => ["image/jpeg"],
    ".jpeg" => ["image/jpeg"],
    ".webp" => ["image/webp"]
  }.freeze

  attr_reader :chat

  def initialize(chat)
    @chat = chat
  end

  def store
    @store ||= RubyLLM::ActiveRecord::FileStore.new(chat)
  end

  # This application's transcript and files are shared with chat participants.
  # Do not expose files owned by a different RubyLLM owner if an application
  # later adds private files to the same chat.
  def files
    chat.ruby_llm_chat_files.where(owner_type: nil, owner_id: nil)
      .with_attached_file.order(updated_at: :desc, id: :desc)
  end

  def find(id)
    files.find(id)
  end

  # Publish a new version on every call. This does not make the native store
  # immutable: write/edit tools can still change files. Business records that
  # need an audit trail must retain a digest/version and enforce that policy.
  def write_artifact(name:, content:, content_type: nil)
    filename = RubyLLM::FileStore.filename(name)
    raise ArgumentError, "artifact filename is too long" if filename.bytesize > MAX_FILENAME_BYTES

    stored = store.write("artifacts/#{SecureRandom.uuid}/#{filename}", content, content_type: content_type)
    files.find_by!(path: stored.path)
  end

  def upload!(upload)
    unless upload.respond_to?(:tempfile) && upload.respond_to?(:original_filename)
      raise InvalidUpload, "Choose a file to upload."
    end

    filename = RubyLLM::FileStore.filename(upload.original_filename)
    if filename.bytesize > MAX_FILENAME_BYTES
      raise InvalidUpload, "Use a filename shorter than #{MAX_FILENAME_BYTES} bytes."
    end
    if upload.size.zero? || upload.size > MAX_UPLOAD_BYTES
      raise InvalidUpload, "Files must be between 1 byte and 25 MB."
    end

    allowed_types = UPLOAD_TYPES[File.extname(filename).downcase]
    upload.tempfile.rewind
    content_type = Marcel::MimeType.for(upload.tempfile, name: filename, declared_type: upload.content_type)
    upload.tempfile.rewind
    unless allowed_types&.include?(content_type)
      raise InvalidUpload, "Upload a PDF, text, Markdown, CSV, JSON, PNG, JPEG, or WebP file."
    end

    # Never let an upload overwrite an agent's output or an earlier source.
    # RubyLLM validates paths; the client cannot choose a storage path or owner.
    stored = store.write("uploads/#{SecureRandom.uuid}/#{filename}", upload.tempfile, content_type: content_type)
    files.find_by!(path: stored.path)
  end
end
