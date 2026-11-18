# frozen_string_literal: true

require "digest"

# One durable owner-private candidate per incoming automation event.
# Until S3/S6, only the explicitly non-AI offline_template origin is allowed.
class AiReplyProposal < ApplicationRecord
  ORIGINS = %w[offline_template].freeze
  STATES = %w[pending applied dismissed].freeze

  belongs_to :ai_automation_run
  belongs_to :room
  belongs_to :user

  validates :ai_automation_run_id, uniqueness: true
  validates :origin, inclusion: { in: ORIGINS }
  validates :state, inclusion: { in: STATES }
  validates :body, presence: true, length: { maximum: Message::MAX_BODY_LENGTH }
  validates :body_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :consistent_scope_and_hash
  validate :immutable_content, on: :update

  def snapshot
    run = ai_automation_run
    { id: id, body: body, state: state, origin: origin,
      source_message_id: run.trigger_message_id,
      provenance: { source_fingerprint: run.source_fingerprint,
        policy_revision: run.policy_revision, goal_revision: run.goal_revision,
        body_sha256: body_sha256 },
      ai_assisted: false, provider_called: false }
  end

  private

  def consistent_scope_and_hash
    if ai_automation_run &&
        (ai_automation_run.run_kind != "reply_proposal" ||
         ai_automation_run.room_id != room_id || ai_automation_run.user_id != user_id)
      errors.add(:ai_automation_run, "must be a review event for this member")
    end
    if body.is_a?(String) && Digest::SHA256.hexdigest(body) != body_sha256
      errors.add(:body_sha256, "must match the saved text")
    end
    if state == "pending" && (applied_at || dismissed_at)
      errors.add(:base, "Pending proposal has a decision timestamp")
    elsif state == "applied" && (applied_at.nil? || dismissed_at)
      errors.add(:base, "Applied proposal requires only applied_at")
    elsif state == "dismissed" && (dismissed_at.nil? || applied_at)
      errors.add(:base, "Dismissed proposal requires only dismissed_at")
    end
  end

  def immutable_content
    %w[ai_automation_run_id room_id user_id origin body body_sha256].each do |field|
      errors.add(:base, "Proposal source and content are immutable") if
        will_save_change_to_attribute?(field)
    end
  end
end
