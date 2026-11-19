require "test_helper"
require "set"

class AiWorkspaceEvidenceChronologyV1Test < ActiveSupport::TestCase
  def hit(id:, at:, cue:, topic: %w[project milestone], speaker: "you")
    { id: id, created_at: at, speaker: speaker,
      classification: { state: cue }, topic_terms: Set.new(topic) }
  end

  test "orders original creation time then ID and describes only tentative links" do
    later = "2026-11-17T10:02:00.000000Z"
    earlier = "2026-11-17T10:01:00.000000Z"
    first = hit(id: 10, at: earlier, cue: "proposal")
    second = hit(id: 11, at: later, cue: "confirmation_candidate", speaker: "participant_2")
    third = hit(id: 12, at: later, cue: "revocation_candidate")

    data = AiWorkspace::EvidenceChronologyV1.call(selected: [third, second, first])
    assert_equal "unverified_candidate_chronology", data.fetch(:state)
    assert_equal "selected_ranked_matches_only", data.fetch(:scope)
    assert_equal [10, 11, 12], data.fetch(:events).map { |row| row.fetch(:id) }
    assert_equal %w[
      possible_response_to_proposal possible_reversal
    ], data.fetch(:links).map { |row| row.fetch(:relation) }
    assert_equal [[10, 11], [11, 12]], data.fetch(:links).map { |row|
      [row.fetch(:earlier_id), row.fetch(:later_id)]
    }
    assert data.fetch(:links).all? { |row|
      row.fetch(:certainty) == "lexical_candidate_only"
    }
    assert_equal "not_determined", data.fetch(:approval_state)
    assert_equal true, data.fetch(:requires_human_review)
  end

  test "a later affirmation cannot retroactively turn a rejection into agreement" do
    base = "2026-11-17T11:00:00.000000Z"
    reject = hit(id: 1, at: base, cue: "rejection_candidate")
    affirm = hit(id: 2, at: "2026-11-17T11:01:00.000000Z",
      cue: "confirmation_candidate")
    result = AiWorkspace::EvidenceChronologyV1.call(selected: [reject, affirm])
    assert_equal "possible_reconfirmation", result.fetch(:links).first.fetch(:relation)
    assert_equal "not_determined", result.fetch(:approval_state)
  end

  test "generic words and mixed cues do not fabricate relationships" do
    first = hit(id: 3, at: "2026-11-17T11:00:00.000000Z",
      cue: "proposal", topic: %w[project terms])
    second = hit(id: 4, at: "2026-11-17T11:01:00.000000Z",
      cue: "confirmation_candidate", topic: %w[project price])
    third = hit(id: 5, at: "2026-11-17T11:02:00.000000Z",
      cue: "mixed_requires_review", topic: %w[project terms])
    assert_empty AiWorkspace::EvidenceChronologyV1.call(
      selected: [first, second, third]
    ).fetch(:links)
  end

  test "rejects invalid IDs or untrusted chronology payloads" do
    [nil, {}, [nil],
      [hit(id: 0, at: "2026-11-17T11:00:00Z", cue: "proposal")],
      [hit(id: 1, at: "not a date", cue: "proposal")],
      [hit(id: 1, at: "2026-11-17T11:00:00Z", cue: "proposal", speaker: "staff:admin")],
      Array.new(13) { |i| hit(id: i + 1, at: "2026-11-17T11:00:00Z", cue: "proposal") }
    ].each do |payload|
      assert_raises(AiWorkspace::Errors::InvalidSelection, payload.inspect) do
        AiWorkspace::EvidenceChronologyV1.call(selected: payload)
      end
    end
  end
end
