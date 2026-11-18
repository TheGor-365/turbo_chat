# frozen_string_literal: true

# User-owned intent, not an execution authorization. Never infer actual
# permission to run a provider, enqueue messages or publish from these fields.
class AiAutomationPolicy < ApplicationRecord
  REPLY_MODES = %w[off review full_auto].freeze
  SUMMARY_MODES = %w[off manual after_messages daily].freeze
  SUMMARY_KINDS = %w[conversation_summary action_items client_brief open_questions].freeze
  PREVIEW_KINDS = %w[conversation_summary client_brief].freeze

  belongs_to :room
  belongs_to :user

  validates :user_id, uniqueness: { scope: :room_id }
  validates :reply_mode, inclusion: { in: REPLY_MODES }
  validates :summary_mode, inclusion: { in: SUMMARY_MODES }
  validates :summary_kind, inclusion: { in: SUMMARY_KINDS }
  validates :summary_after_messages, numericality: { only_integer: true, in: 5..200 }
  validates :reply_delay_seconds, numericality: { only_integer: true, in: 10..600 }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }

  def public_snapshot
    { reply_mode: reply_mode, summary_mode: summary_mode,
      summary_kind: summary_kind, summary_after_messages: summary_after_messages,
      reply_delay_seconds: reply_delay_seconds, revision: revision }
  end

  # Explicitly fail-closed until dedicated provider budget, worker, event
  # idempotency, consent and final message write gate are implemented.
  def execution_status
    { reply_generation_active: false, unattended_send_active: false,
      scheduled_summaries_active: false, configuration_only: true,
      available_manual_previews: PREVIEW_KINDS }
  end
end
