# frozen_string_literal: true

# FCC-2e.2a. A participant's explicit, version-bound position regarding ONE
# original room message. Append-only activity; never AI-inferred consensus.
# No source text, attachments, provider data or participant identity snapshots.
class CreateAiEvidenceReviewEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_evidence_review_events do |t|
      t.references :room, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.string :source_version_sha256, limit: 64, null: false
      t.string :stance, limit: 20, null: false
      t.string :request_key, limit: 36, null: false
      t.datetime :created_at, null: false
    end

    add_index :ai_evidence_review_events, [:reviewer_id, :request_key],
      unique: true, name: "index_ai_evidence_reviews_idempotency"
    add_index :ai_evidence_review_events,
      [:room_id, :message_id, :reviewer_id, :id],
      name: "index_ai_evidence_reviews_latest"
    add_check_constraint :ai_evidence_review_events,
      "stance IN ('acknowledged', 'disputed', 'withdrawn')",
      name: "ai_evidence_reviews_allowed_stance"
    add_check_constraint :ai_evidence_review_events,
      "length(source_version_sha256) = 64",
      name: "ai_evidence_reviews_version_length"
  end
end
