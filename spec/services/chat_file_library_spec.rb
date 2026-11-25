# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatFileLibrary do
  let(:chat) { chats(:alice_personal_chat) }
  let(:library) { described_class.new(chat) }

  it "keeps file ownership independent of the run receiving usage accounting" do
    run = chat.chat_runs.create!(status: :completed, initiated_by_member: chat.member)
    file = RubyLLM.with_owner(run) do
      library.write_artifact(name: "summary.md", content: "# Summary")
    end

    expect(file.owner).to be_nil
    expect(RubyLLM::ActiveRecord::FileStore.new(Chat.find(chat.id)).read(file.path)).to eq("# Summary")
  end

  it "uses a fresh path for each published artifact" do
    original = library.write_artifact(name: "summary.md", content: "Original")
    revision = library.write_artifact(name: "summary.md", content: "Revised")

    expect(original.path).not_to eq(revision.path)
    expect(library.store.read(original.path)).to eq("Original")
    expect(library.store.read(revision.path)).to eq("Revised")
  end

  it "confines client filenames to the upload namespace" do
    Tempfile.create("chat-document") do |source|
      source.write("Project brief")
      source.rewind
      upload = double(tempfile: source, original_filename: "../../summary.txt", size: source.size, content_type: "text/plain")

      file = library.upload!(upload)

      expect(file.path).to match(%r{\Auploads/[\h-]+/summary\.txt\z})
      expect(library.store["summary.txt"]).to be_nil
    end
  end

  it "rejects oversized files before uploading content to Active Storage" do
    upload = double(tempfile: StringIO.new("large"), original_filename: "large.txt", size: described_class::MAX_UPLOAD_BYTES + 1)

    expect { library.upload!(upload) }.to raise_error(described_class::InvalidUpload, /25 MB/)
    expect(library.files).to be_empty
  end

  it "rejects empty files and excessively long filenames" do
    empty = double(tempfile: StringIO.new, original_filename: "empty.txt", size: 0)
    long = double(tempfile: StringIO.new("text"), original_filename: "a" * 181 + ".txt", size: 4)

    expect { library.upload!(empty) }.to raise_error(described_class::InvalidUpload)
    expect { library.upload!(long) }.to raise_error(described_class::InvalidUpload)
  end
end
