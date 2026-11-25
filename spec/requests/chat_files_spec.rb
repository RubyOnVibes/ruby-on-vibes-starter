# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat files", type: :request do
  let(:alice) { users(:alice) }
  let(:chat) { chats(:alice_personal_chat) }
  let(:library) { ChatFileLibrary.new(chat) }

  before do
    sign_in alice
    patch start_session_workspace_path(workspaces(:alice_personal))
  end

  def uploaded_document(name: "brief.txt", contents: "A new project brief", type: "text/plain")
    Tempfile.create([ "chat-upload", File.extname(name) ]) do |source|
      source.binmode
      source.write(contents)
      source.rewind
      Rack::Test::UploadedFile.new(source.path, type, original_filename: name)
    end
  end

  it "stores uploads in the native store and makes them available after reloading the chat" do
    post chat_files_path(chat), params: { file: uploaded_document }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:created)
    data = response.parsed_body
    reloaded_store = RubyLLM::ActiveRecord::FileStore.new(Chat.find(chat.id))
    expect(reloaded_store.read(data.fetch("path"))).to eq("A new project brief")
    expect(data.fetch("path")).to match(%r{\Auploads/[\h-]+/brief\.txt\z})
    expect(data.fetch("download_url")).to eq(chat_file_path(chat, data.fetch("id")))
  end

  it "keeps separate source versions when the same filename is uploaded twice" do
    2.times do
      post chat_files_path(chat), params: { file: uploaded_document }, headers: { "ACCEPT" => "application/json" }
    end

    expect(library.files.count).to eq(2)
    expect(library.files.pluck(:path).uniq.size).to eq(2)
  end

  it "rejects executable and active document uploads without storing blobs" do
    expect do
      post chat_files_path(chat), params: {
        file: uploaded_document(name: "payload.html", contents: "<script>alert(1)</script>", type: "text/html")
      }, headers: { "ACCEPT" => "application/json" }
    end.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a missing upload" do
    post chat_files_path(chat), params: {}, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "serves a useful authenticated files page" do
    library.write_artifact(name: "summary.md", content: "# Summary")

    get chat_files_path(chat)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("summary.md", "Upload file", "Back to chat")
  end

  it "downloads generated active content as an attachment without issuing a public blob URL" do
    file = library.write_artifact(name: "report.html", content: "<h1>Report</h1>", content_type: "text/html")

    get chat_file_path(chat, file)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<h1>Report</h1>")
    expect(response.media_type).to eq("application/octet-stream")
    expect(response.headers.fetch("Content-Disposition")).to start_with("attachment;")
    expect(response.headers.fetch("Cache-Control")).to include("private", "no-store")
    expect(response.headers.fetch("X-Content-Type-Options")).to eq("nosniff")
  end

  it "never returns a file from another chat even when the member can access both chats" do
    other_chat = Chat.create!(member: members(:alice_personal_member))
    file = ChatFileLibrary.new(other_chat).write_artifact(name: "private.txt", content: "Other conversation")

    get chat_file_path(chat, file), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "does not let another workspace member list or upload to this chat" do
    sign_out alice
    sign_in users(:bob)
    patch start_session_workspace_path(workspaces(:bob_personal))

    get chat_files_path(chat), as: :json
    expect(response).to have_http_status(:not_found)

    expect do
      post chat_files_path(chat), params: { file: uploaded_document }, headers: { "ACCEPT" => "application/json" }
    end.not_to change(RubyLLM::ActiveRecord::ChatFile, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "hides owner-private native files from the shared file list and download route" do
    private_store = RubyLLM::ActiveRecord::FileStore.new(chat, owner: members(:alice_personal_member))
    private_store.write("private.txt", "Private file")
    private_file = chat.ruby_llm_chat_files.find_by!(path: "private.txt")

    get chat_files_path(chat), as: :json
    expect(response.parsed_body).to be_empty

    get chat_file_path(chat, private_file), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication to download an artifact" do
    file = library.write_artifact(name: "summary.md", content: "# Summary")
    sign_out alice

    get chat_file_path(chat, file)

    expect(response).to redirect_to(new_user_session_path)
  end
end
