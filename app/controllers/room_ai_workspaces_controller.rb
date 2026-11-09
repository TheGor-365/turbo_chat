class RoomAiWorkspacesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_authorized_room
  before_action :limit_previews, only: :preview

  def show
    load_view
  end

  # This never contacts a model or writes a request. It only shows a safe,
  # bounded local preview of text the member explicitly selected.
  def preview
    details = params.require(:review).permit(:operation, :preset_id, message_ids: [])
    @requested_operation = details[:operation]
    @requested_preset_id = details[:preset_id]

    # Pre-2B request payloads (without a preset_id) remain supported.
    if @requested_preset_id.present?
      preset = AiWorkspace::PresetRegistry.bundled.fetch(@requested_preset_id)
      unless preset.operation == @requested_operation
        raise AiWorkspace::Errors::InvalidPreset, "Incompatible preset."
      end
      prepared = AiWorkspace::ContentPipeline.new.prepare(
        actor: current_user, room: @room, source: "selected_messages",
        source_ids: details[:message_ids], operation: @requested_operation,
        preset: preset
      )
    end

    review = AiWorkspace::Scope.new(
      room: @room, actor: current_user, operation: @requested_operation,
      message_ids: details[:message_ids]
    ).review
    @preset = preset
    @preparation = prepared
    @review = review
    load_view
    render :show
  rescue AiWorkspace::Scope::Unauthorized, AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Scope::InvalidSelection => error
    @review_error = error.message
    load_view
    render :show, status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidPreset, AiWorkspace::Errors::InvalidSelection,
    AiWorkspace::Errors::ConsentRequired
    @review_error = "Preset or selected context is unavailable."
    load_view
    render :show, status: :unprocessable_entity
  end

  private

  def load_authorized_room
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_previews
    enforce_request_limit(scope: "ai-scope-preview", limit: 12, period: 60.seconds)
  end

  def load_view
    # Full history is NEVER collected implicitly for AI. The selection list
    # is bounded, contains only visible text and does not load file bytes.
    @candidate_messages = @room.messages
      .where("NULLIF(TRIM(messages.body), '') IS NOT NULL")
      .includes(:user).order(created_at: :desc, id: :desc)
      .limit(20).reverse

    @conversation_label = if @room.direct_message?
      @room.participants.includes(:user)
        .find { |membership| membership.user_id != current_user.id }
        &.user&.chat_label || "Direct conversation"
    else
      @room.name
    end
    @presets = AiWorkspace::PresetRegistry.bundled.all
    @operation_for_form = @review&.operation ||
      (AiWorkspace::Scope::OPERATIONS.key?(@requested_operation) ? @requested_operation : "summarize")
    compatible = @presets.select { |preset| preset.operation == @operation_for_form }
    @chosen_preset_id = if @preset
      @preset.id
    elsif compatible.any? { |preset| preset.id == @requested_preset_id }
      @requested_preset_id
    else
      compatible.first&.id
    end
    @preset_select_options = @presets.map do |preset|
      [preset.label, preset.id, {
        "data-operation" => preset.operation, "data-version" => preset.version,
        "data-tone" => preset.snapshot.fetch("tone"),
        "data-style" => preset.snapshot.fetch("style"),
        "data-limit" => preset.snapshot.dig("context", "max_messages")
      }]
    end
    warning_labels = {
      possible_email: "possible email address", possible_secret: "possible secret",
      source_truncated: "truncated source"
    }
    @preset_warning_labels = @preparation ? @preparation.rows.flat_map(&:warnings).uniq.map do |warning|
      warning_labels.fetch(warning)
    end : []
    @selected_ids = @review&.rows&.map(&:message_id) || []
  end
end
