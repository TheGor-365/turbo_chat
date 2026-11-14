class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_message_writes, only: %i[create update destroy]
  before_action :load_owned_message, only: %i[edit update destroy]
  before_action :limit_sync_requests, only: :sync
  before_action :limit_message_searches, only: :search

  def create
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    upload_error = AttachmentUploadGuard.error_for(params.dig(:message, :attachments))
    if upload_error
      return respond_to do |format|
        format.html { redirect_to room_path(@room), alert: upload_error }
        format.turbo_stream { render plain: upload_error, content_type: "text/plain", status: :unprocessable_entity }
      end
    end

    @message = @room.messages.build(msg_params)
    # A reply target is scoped to the authorized room on the server,
    # never resolved as a global message id supplied by the browser.
    if @message.reply_to_id.present?
      @message.reply_to = @room.messages.find_by(id: @message.reply_to_id)
      unless @message.reply_to
        return respond_to do |format|
          format.html { redirect_to room_path(@room), alert: "Reply target is unavailable" }
          format.turbo_stream { render plain: "Reply target is unavailable", content_type: "text/plain", status: :unprocessable_entity }
        end
      end
    end
    @message.user = current_user

    if @message.save
      respond_to do |format|
        format.html { redirect_to room_path(@room) }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to room_path(@room), alert: @message.errors.full_messages.to_sentence }
        # Return only safe validation text to the owner of this submission;
        # the composer displays it as text, never HTML, and preserves its draft.
        format.turbo_stream { render plain: @message.errors.full_messages.to_sentence, content_type: "text/plain", status: :unprocessable_entity }
      end
    end
  end

  # Search is deliberately scoped to one currently authorized conversation.
  # No global inbox search, attachment text extraction or user-email lookup.
  def search
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @query = params[:q].to_s.strip
    return head :bad_request if @query.length > 100

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    if @query.length >= 2
      escaped = ActiveRecord::Base.sanitize_sql_like(@query)
      scope = @room.messages
        .where("messages.body ILIKE ?", "%#{escaped}%")
        .includes(:user)
        .order(created_at: :desc, id: :desc)
      @pagy, @results = pagy(scope, items: 15)
    else
      @results = []
    end
  rescue Pagy::OverflowError
    head :not_found
  end

  # Bounded message recovery after dropped or stale Action Cable subscriptions.
  # In addition to new messages, the client may recheck versions of up to 30
  # message elements that it actually rendered. This repairs missed edits and
  # deletions without reloading a whole conversation or touching older pages.
  def sync
    room = Room.find(params[:room_id])
    return head :forbidden unless room.accessible_to?(current_user)

    cursor = params.fetch(:after_id, "0").to_s
    return head :bad_request unless cursor.match?(/\A\d{1,18}\z/)

    recheck = params[:recheck].to_s
    recheck_versions = {}
    if params.key?(:recheck)
      # 30 pairs max, <=18 decimal digits per ID and microsecond timestamp.
      # Reject malformed/oversized input before any message lookup.
      pair = "[1-9]\\d{0,17}:[1-9]\\d{0,17}"
      return head :bad_request if recheck.bytesize > 1_200 ||
        !recheck.match?(/\A#{pair}(?:,#{pair}){0,29}\z/)
      recheck.split(",").each do |entry|
        id, version = entry.split(":", 2).map!(&:to_i)
        return head :bad_request if recheck_versions.key?(id)
        recheck_versions[id] = version
      end
    end

    messages = room.messages
      .where("messages.id > ?", cursor.to_i)
      .includes(:user, :message_reactions, attachments_attachments: :blob)
      .order(:id)
      .limit(50)
      .to_a

    streams = []
    if recheck_versions.any?
      current = room.messages.where(id: recheck_versions.keys)
        .includes(:user, :message_reactions, reply_to: :user, attachments_attachments: :blob)
        .index_by(&:id)
      recheck_versions.each do |id, version|
        message = current[id]
        if message.nil?
          streams << turbo_stream.remove("message_#{id}")
        elsif (message.updated_at.to_r * 1_000_000).to_i != version
          streams << turbo_stream.replace(
            "message_#{id}",
            partial: "messages/message",
            locals: { message: message, viewer: current_user }
          )
        end
      end
    end

    streams << turbo_stream.append(
      "messages-container",
      partial: "messages/message",
      collection: messages,
      as: :message,
      locals: { viewer: current_user }
    )

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Chat-Last-Id"] = messages.last&.id.to_s
    response.headers["X-Chat-More"] = messages.length == 50 ? "1" : "0"

    render turbo_stream: streams
  end

  def edit
  end

  def update
    if @message.update(body_params)
      respond_to do |format|
        format.html { redirect_to room_path(@room), notice: "Message updated" }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_room_message_path(@room, @message), alert: @message.errors.full_messages.to_sentence }
        format.turbo_stream { render plain: @message.errors.full_messages.to_sentence, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @message.destroy!
    respond_to do |format|
      format.html { redirect_to room_path(@room), notice: "Message deleted" }
      format.turbo_stream { render turbo_stream: turbo_stream.remove("message_#{@message.id}") }
    end
  end

  private

  def limit_sync_requests
    enforce_request_limit(scope: "message-sync", limit: 15, period: 60.seconds)
  end

  def limit_message_searches
    enforce_request_limit(scope: "message-search", limit: 25, period: 60.seconds)
  end

  def load_owned_message
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @message = @room.messages.find(params[:id])
    head :forbidden unless @message.user_id == current_user.id
  end

  def body_params
    params.require(:message).permit(:body)
  end

  def limit_message_writes
    enforce_request_limit(scope: "message-create", limit: 30, period: 60.seconds)
  end

  def msg_params
    params.require(:message).permit(:body, :reply_to_id, attachments: [])
  end
end
