# frozen_string_literal: true

# Personal account preference only. Never author consent or a spend permit.
class AiPersonalEnablement < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: true
  validates :enabled, inclusion: { in: [true, false] }

  def revision
    lock_version + 1
  end
end
