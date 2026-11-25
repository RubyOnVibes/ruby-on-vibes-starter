# frozen_string_literal: true

class ChatFilesController < ApplicationController
  before_action :require_chat_enabled!
  before_action :set_chat

  def index
    authorize @chat, :show?
    @files = @library.files

    respond_to do |format|
      format.html
      format.json { render json: @files.map { |file| file_json(file) } }
    end
  end

  def create
    authorize @chat, :send_messages?
    file = @library.upload!(params[:file])

    respond_to do |format|
      format.html { redirect_to chat_files_path(@chat), notice: "File added. Your assistant can now read it.", status: :see_other }
      format.json { render json: file_json(file), status: :created }
    end
  rescue ChatFileLibrary::InvalidUpload => error
    respond_to do |format|
      format.html do
        @files = @library.files
        flash.now[:alert] = error.message
        render :index, status: :unprocessable_content
      end
      format.json { render json: { error: error.message }, status: :unprocessable_content }
    end
  end

  def show
    authorize @chat, :show?
    file = @library.find(params[:id])
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data file.file.download,
      filename: File.basename(file.path),
      type: "application/octet-stream",
      disposition: "attachment"
  end

  private

  def set_chat
    @chat = current_member.chats.find(params[:chat_id])
    @library = ChatFileLibrary.new(@chat)
  end

  def file_json(file)
    {
      id: file.id,
      path: file.path,
      filename: File.basename(file.path),
      byte_size: file.byte_size,
      content_type: file.content_type,
      updated_at: file.updated_at,
      download_url: chat_file_path(@chat, file)
    }
  end
end
