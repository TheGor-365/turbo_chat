# frozen_string_literal: true

# PostgreSQL record of a budget reservation. This is not permission to invoke
# a provider; actual inference still requires separate ACL and consent gates.
class AiUsageReservation < ApplicationRecord
  STATES = %w[reserved uncertain settled].freeze
  PURPOSES = %w[beautify contextual_answer reply_proposal reply_unattended conversation_outcome translation].freeze
  SHA = /\A[0-9a-f]{64}\z/

  belongs_to :user
  belongs_to :room

  validates :request_key_hash, format: { with: SHA }, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :state, inclusion: { in: STATES }
  validates :reserved_ticks, numericality: { only_integer: true, greater_than: 0 }
  validates :allocated_ticks, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :actual_ticks, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :day_utc, :month_utc, presence: true
  validate :settlement_consistency

  # Identity and scope are immutable. State/cost may change only in the ledger.
  attr_readonly :request_key_hash, :user_id, :room_id, :purpose,
    :reserved_ticks, :day_utc, :month_utc

  private

  def settlement_consistency
    if state == "settled"
      errors.add(:actual_ticks, "required") if actual_ticks.nil?
      errors.add(:allocated_ticks, "must equal actual cost") if
        actual_ticks && allocated_ticks != actual_ticks
    elsif actual_ticks.present?
      errors.add(:actual_ticks, "must remain unknown until settled")
    elsif allocated_ticks != reserved_ticks
      errors.add(:allocated_ticks, "must retain reservation while cost is unknown")
    end
  end
end
