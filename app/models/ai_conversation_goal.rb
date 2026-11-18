# frozen_string_literal: true

# Personal lower-trust goal text. It is not a room policy, an AI system prompt,
# a grant to read history, a purchase authorization or an auto-send policy.
class AiConversationGoal < ApplicationRecord
  belongs_to :room
  belongs_to :user

  CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u202A-\u202E\u2066-\u2069]/
  POSSIBLE_SECRET = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|xai-[A-Za-z0-9_-]{20,})\b/i

  before_validation :normalize_text
  validates :user_id, uniqueness: { scope: :room_id }
  validates :purpose, presence: true, length: { maximum: 500 }
  validates :constraints, length: { maximum: 1000 }
  validates :desired_outcome, length: { maximum: 500 }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validate :reject_unsafe_text

  def public_snapshot
    { purpose: purpose, constraints: constraints,
      desired_outcome: desired_outcome, revision: revision, active: active? }
  end

  private

  def normalize_text
    self.purpose = purpose.strip if purpose.is_a?(String)
    self.constraints = constraints.strip if constraints.is_a?(String)
    self.desired_outcome = desired_outcome.strip if desired_outcome.is_a?(String)
  end

  def reject_unsafe_text
    %i[purpose constraints desired_outcome].each do |attribute|
      text = public_send(attribute)
      next if text.blank? || !text.is_a?(String)
      errors.add(attribute, :invalid) if CONTROL.match?(text) || POSSIBLE_SECRET.match?(text)
    end
  end
end
