# Chat files and artifacts

Files use RubyLLM's `ruby_llm_chat_files` records and Active Storage blobs. The application adds a small authorization and upload boundary; it does not duplicate RubyLLM's file store, conversion cache, read digests, or file tools.

Open **Files and artifacts** from a chat to upload source documents and download generated files. `GET /chats/:chat_id/files.json` lists metadata and authenticated download URLs; multipart `POST /chats/:chat_id/files` accepts a single `file`. Uploads accept PDF, text, Markdown, CSV, JSON, PNG, JPEG, and WebP, up to 25 MB. Application code can adjust this allowlist in `ChatFileLibrary`. Files are available to the assistant on its next turn; uploading alone does not start a run.

Every route authenticates the user, scopes the chat to their current workspace membership, and applies `ChatPolicy`. Downloads then scope the file to that chat and the shared, ownerless file set. They stream bytes as an attachment through the authorized controller; the API never exposes Active Storage signed blob URLs. Potentially active generated content is downloaded as `application/octet-stream` with `nosniff` and private, no-store caching.

Rails' default signed Active Storage routes still exist because the existing message attachment previews use them. Those signed URLs act as bearer links and do not recheck chat membership. The new file API does not issue them. Applications requiring revocable access for *all* attachments should also migrate message previews to authenticated routes before disabling Active Storage's default routes.

Chat participants share transcripts and files. Leave native chat ownership unset: `RubyLLM.with_owner(chat_run)` attributes usage to a run without making its files private to that temporary run. If an application introduces private files, define the ownership policy explicitly and add corresponding access routes; the shared routes deliberately exclude owner-private native files.

## Using files from application code

After authorizing a chat:

```ruby
library = ChatFileLibrary.new(chat)
file = library.upload!(params[:file])

# Native APIs remain available to tools and agents.
library.store.read(file.path)
library.store.write("working/notes.md", "Draft notes")

# Publish a new version without overwriting an existing output.
artifact = library.write_artifact(
  name: "summary.md",
  content: "# Document summary\n...",
  content_type: "text/markdown"
)
```

Upload paths are `uploads/<uuid>/<filename>` and published artifact paths are `artifacts/<uuid>/<filename>`. The client cannot choose a path, owner, or existing blob. Repeated filenames create separate versions.

These are versioned naming conventions, **not an immutable audit store**. RubyLLM's native write/edit tools can modify files. A business record requiring immutable evidence should capture its source/output digest, retain versions, and enforce its own publication policy. External side effects should use the business operation's idempotency key; calling `write_artifact` twice intentionally creates two files.

The same Active Storage service must be available to web and worker processes. Local SQLite development uses disk storage; multi-host deployments should configure shared object storage. Files may be untrusted source material: agent instructions and tools must treat their contents as data, and approval decisions must stay in application authorization code.

`ruby_llm_file_store_connection.rb` is a narrow compatibility shim for RubyLLM 2.2.3's deprecated `ActiveRecord.connection` call during file writes. It preserves the template's permanent-checkout protection and borrows a connection around the native lock helper. Remove it when RubyLLM uses `with_connection` upstream; the request specs exercise this compatibility boundary.
