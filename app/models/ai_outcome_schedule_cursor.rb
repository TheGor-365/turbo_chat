# frozen_string_literal: true

class AiOutcomeScheduleCursor < ApplicationRecord
  belongs_to :ai_automation_policy

  validates :ai_automation_policy_id, uniqueness: true
  validates :policy_revision, numericality: { only_integer: true, greater_than: 0 }
  validates :last_message_id, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
