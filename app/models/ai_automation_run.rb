# frozen_string_literal: true

# Execution metadata only. "recorded" never means queued, paid, generated,
# approved or sent. A separate audited worker will be required for execution.
class AiAutomationRun < ApplicationRecord
  KINDS = %w[reply_proposal reply_unattended conversation_outcome].freeze
  STATUSES = %w[recorded canceled].freeze
  CANCELLATION_REASONS = %w[policy_changed policy_disabled].freeze

  belongs_to :room
  belongs_to :user
  belongs_to :ai_automation_policy
  belongs_to :trigger_message, class_name: "Message", optional: true
  has_one :ai_automation_work_item, dependent: :destroy
  has_one :ai_reply_proposal, dependent: :destroy

  validates :run_kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :event_key, :source_fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :policy_revision, numericality: { only_integer: true, greater_than: 0 }
  validates :goal_revision, numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :cancellation_reason, inclusion: { in: CANCELLATION_REASONS },
    allow_nil: true
  validate :consistent_scope_and_sources
  validate :outcome_window_scope
  validate :immutable_event_identity, on: :update

  def outcome_source_options
    { after_message_id: source_after_message_id,
      through_message_id: source_through_message_id, utc_day: source_utc_day }
  end

  def self.cancel_obsolete!(room:, user:, current_revision:, reason:)
    raise ArgumentError, "invalid cancellation reason" unless CANCELLATION_REASONS.include?(reason)

    where(room_id: room.id, user_id: user.id, status: "recorded")
      .where("policy_revision < ?", current_revision)
      .update_all(status: "canceled", cancellation_reason: reason,
        canceled_at: Time.current, updated_at: Time.current)
  end

  private

  def consistent_scope_and_sources
    if ai_automation_policy && (ai_automation_policy.room_id != room_id ||
        ai_automation_policy.user_id != user_id)
      errors.add(:ai_automation_policy, "must belong to the same room member")
    end
    unless source_message_ids.is_a?(Array) &&
        source_message_ids.size.between?(1, AiWorkspace::ReplyContextBuilder::MAX_MESSAGES) &&
        source_message_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
        source_message_ids.uniq == source_message_ids
      errors.add(:source_message_ids, "must be a bounded unique list")
    end
    if run_kind == "conversation_outcome"
      errors.add(:trigger_message, "must be blank") if trigger_message_id.present?
    elsif !source_message_ids.include?(trigger_message_id)
      errors.add(:trigger_message, "must be an included source")
    end
  end

  def outcome_window_scope
    unless source_after_message_id.nil? ||
        (source_after_message_id.is_a?(Integer) && source_after_message_id >= 0)
      errors.add(:source_after_message_id, "is invalid")
    end
    unless source_through_message_id.nil? ||
        (source_through_message_id.is_a?(Integer) && source_through_message_id.positive?)
      errors.add(:source_through_message_id, "is invalid")
    end
    if source_after_message_id && source_through_message_id &&
        source_after_message_id >= source_through_message_id
      errors.add(:source_through_message_id, "must exceed starting ID")
    end
    if source_utc_day && (source_after_message_id || source_through_message_id)
      errors.add(:source_utc_day, "must not overlap an ID range")
    end
    if run_kind != "conversation_outcome" &&
        (source_after_message_id || source_through_message_id || source_utc_day)
      errors.add(:base, "Reply events cannot set outcome windows")
    end
  end

  def immutable_event_identity
    immutable = %w[room_id user_id ai_automation_policy_id trigger_message_id run_kind
      event_key source_fingerprint source_message_ids policy_revision goal_revision
      source_after_message_id source_through_message_id source_utc_day]
    errors.add(:base, "Automation event identity is immutable") if
      immutable.any? { |field| will_save_change_to_attribute?(field) }
  end
end
