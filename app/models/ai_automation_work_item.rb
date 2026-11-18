# frozen_string_literal: true

# A durable queue entry, not a payment or permission. Restrict execution to
# H4 offline evidence digests until the provider/Send gates are implemented.
class AiAutomationWorkItem < ApplicationRecord
  STATES = %w[queued leased completed blocked].freeze
  FAILURE_CODES = %w[consent_or_source_changed unsupported_outcome].freeze
  MAX_ATTEMPTS = 3

  belongs_to :ai_automation_run
  belongs_to :ai_deliverable, optional: true

  validates :ai_automation_run_id, uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :attempts, numericality: { only_integer: true, in: 0..MAX_ATTEMPTS }
  validates :lease_token, format: { with: /\A[0-9a-f]{64}\z/ },
    allow_nil: true
  validates :failure_code, inclusion: { in: FAILURE_CODES }, allow_nil: true
  validate :state_consistency

  private

  def state_consistency
    if state == "leased"
      errors.add(:lease_token, "required") if lease_token.blank?
      errors.add(:lease_until, "required") if lease_until.blank?
    elsif lease_token.present? || lease_until.present?
      errors.add(:base, "Lease must be cleared after processing")
    end
    if state == "completed"
      errors.add(:ai_deliverable, "required") unless ai_deliverable
      errors.add(:completed_at, "required") if completed_at.blank?
    elsif ai_deliverable_id.present?
      errors.add(:ai_deliverable, "must be absent until completion")
    end
  end
end
