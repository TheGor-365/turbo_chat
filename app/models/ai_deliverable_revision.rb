# frozen_string_literal: true

class AiDeliverableRevision < ApplicationRecord
  MAX_BODY_CHARS = 5_000

  belongs_to :ai_deliverable, inverse_of: :revisions
  belongs_to :author, class_name: "User"

  validates :version, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :ai_deliverable_id }
  validates :body_markdown, presence: true, length: { maximum: MAX_BODY_CHARS }
  validates :body_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :source_ids_are_safe

  before_update { raise ActiveRecord::ReadOnlyError, "Revisions are immutable" }
  before_destroy { raise ActiveRecord::ReadOnlyError, "Revisions are immutable" }

  private

  def source_ids_are_safe
    unless source_message_ids.is_a?(Array) &&
        source_message_ids.length <= AiWorkspace::ReplyContextBuilder::MAX_MESSAGES &&
        source_message_ids.uniq == source_message_ids &&
        source_message_ids.all? { |id| id.is_a?(Integer) && id.positive? }
      errors.add(:source_message_ids, "are invalid")
    end
  end
end
