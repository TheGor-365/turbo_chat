# frozen_string_literal: true

# S8/D5: the single contextual message inventory for the AI Context Studio.
# This is a read-only, unanimous-consent-scoped UI inventory, NOT a grant to
# transmit all these messages to a provider. Provider input remains bounded by
# ReplyContextBuilder until the subsequent full-history retrieval slice.
class RoomAiContextMessagesController < ApplicationController
  PAGE_SIZE = 25
  MAX_QUERY_CHARS = 120

  before_action :authenticate_user!
  before_action :limit_requests

  def index
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    page = params[:page].presence || "1"
    return head :unprocessable_entity unless page.is_a?(String) &&
      page.match?(/\A[1-9]\d{0,3}\z/)

    query = params[:q].to_s.strip
    return head :unprocessable_entity if query.length > MAX_QUERY_CHARS ||
      query.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/)

    member_ids = room.participants.distinct.pluck(:user_id).sort
    author = params[:author_id].presence
    if author && (!author.is_a?(String) || !author.match?(/\A[1-9]\d{0,17}\z/) ||
        !member_ids.include?(author.to_i))
      return head :unprocessable_entity
    end

    range = {}
    %w[from to].each do |field|
      next if params[field].blank?
      value = params[field]
      return head :unprocessable_entity unless value.is_a?(String) &&
        value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      begin
        range[field] = Date.iso8601(value)
      rescue Date::Error
        return head :unprocessable_entity
      end
    end
    return head :unprocessable_entity if range["from"] && range["to"] &&
      range["from"] > range["to"]

    snapshot = AiWorkspace::ConversationCoverageSnapshotV2.new
    before = snapshot.build(room: room, actor: current_user)
    safe_versions = before.sources.index_by(&:message_id)
    scope = room.messages.where(id: safe_versions.keys)
    scope = scope.where(user_id: author.to_i) if author
    if query.present?
      scope = scope.where("messages.body ILIKE ?",
        "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
    scope = scope.where("messages.created_at >= ?", range["from"].beginning_of_day) if range["from"]
    scope = scope.where("messages.created_at < ?", range["to"].next_day.beginning_of_day) if range["to"]

    total = scope.count
    rows = scope.order(created_at: :desc, id: :desc)
      .limit(PAGE_SIZE).offset((page.to_i - 1) * PAGE_SIZE)
      .select(:id, :user_id, :body, :created_at, :updated_at).to_a

    # A message edited after the inventory snapshot must never leak text based
    # on the earlier DLP result. Compare source versions and a new full report.
    items = rows.map do |message|
      source = safe_versions.fetch(message.id)
      checked = AiWorkspace::Preprocessors::Text.call(message.body)
      raise AiWorkspace::Errors::InvalidSelection if checked.warnings.any? ||
        checked.text.strip.empty? ||
        Digest::SHA256.hexdigest(message.body) != source.body_sha256 ||
        message.updated_at&.utc&.iso8601(6) != source.updated_at
      { id: message.id, author_id: message.user_id,
        created_at: message.created_at.utc.iso8601,
        text: checked.text, incoming: message.user_id != current_user.id }
    end
    after = snapshot.build(room: room.reload, actor: current_user)
    unless before.source_sha256 == after.source_sha256 &&
        before.consent_sha256 == after.consent_sha256
      raise AiWorkspace::Errors::InvalidSelection
    end

    names = User.where(id: member_ids).index_by(&:id)
    per_author = before.sources.group_by(&:author_id).transform_values(&:size)
    participants = member_ids.map do |id|
      { id: id, name: names.fetch(id).chat_label, own: id == current_user.id,
        eligible_count: per_author.fetch(id, 0) }
    end
    render json: {
      version: 1, room_id: room.id, state: "local_review_only",
      full_history_covered: true, model_receives_full_history: false,
      eligible_total: before.included_text_messages,
      excluded_total: before.total_messages - before.included_text_messages,
      filtered_total: total, page: page.to_i, page_size: PAGE_SIZE,
      has_more: page.to_i * PAGE_SIZE < total,
      snapshot_fingerprint: Digest::SHA256.hexdigest(
        before.source_sha256 + before.consent_sha256),
      latest_incoming_id: before.sources.reverse.find { |source|
        source.author_id != current_user.id }&.message_id,
      participants: participants, messages: items
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection
    render json: {error: "context_stale_or_consent_missing"}, status: :unprocessable_entity
  end

  private

  def limit_requests
    enforce_request_limit(scope: "ai-context-studio-inventory", limit: 20,
      period: 60.seconds)
  end
end
