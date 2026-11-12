# frozen_string_literal: true

class AiDeliverable < ApplicationRecord
  KINDS = AiWorkspace::StructuredDeliverableV1::SECTIONS.keys.freeze
  STATES = %w[draft in_review approved archived].freeze

  belongs_to :room
  belongs_to :owner, class_name: "User"
  has_many :revisions, class_name: "AiDeliverableRevision",
    dependent: :destroy, inverse_of: :ai_deliverable

  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }

  def latest_revision
    revisions.order(version: :desc).first
  end
end
