require "test_helper"

class AiWorkspaceStructuredDeliverableV1Test < ActiveSupport::TestCase
  def bundle
    rows = [
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: 29, speaker: "participant_1",
        text: "The checkout endpoint returns HTTP 422.", truncated: false
      ).freeze,
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: 30, speaker: "you",
        text: "We should inspect the validation errors.", truncated: false
      ).freeze
    ]
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: rows.freeze,
      source_ids: [29, 30].freeze, characters: 100, omitted: 0
    ).freeze
  end

  def draft(kind: "client_brief", entries: nil, source: bundle)
    AiWorkspace::StructuredDeliverableV1.build!(
      kind: kind, bundle: source, entries: entries || [
        { section: "requirements", text: "Investigate HTTP 422 [M29]",
          status: "inferred", source_ids: [29] },
        { section: "open_questions", text: "Deadline: to confirm",
          status: "needs_confirmation", source_ids: [] }
      ]
    )
  end

  test "H4 brief: permitted source provenance does not confirm AI claims" do
    document = draft
    assert_equal "client_brief", document.kind
    assert_equal 1, document.version
    assert_equal 3, document.room_id
    assert_equal [29, 30], document.source_ids
    assert_equal "pending_manual_review", document.review_state
    assert_equal %w[inferred needs_confirmation], document.entries.map(&:status)
    assert_nil document.entries.first.reviewed_by_actor_id
    assert_equal [29], document.entries.first.source_ids
    assert document.frozen?
    assert document.entries.frozen?
    assert document.entries.first.frozen?
    assert document.entries.first.text.frozen?
    assert document.entries.first.source_ids.frozen?
  end

  test "H4 proposal and summary have different code-owned sections" do
    proposal = draft(kind: "client_proposal", entries: [
      { section: "assumptions", text: "We may need more diagnostics [M29]",
        status: "inferred", source_ids: [29] }
    ])
    summary = draft(kind: "conversation_summary", entries: [
      { section: "decisions", text: "No decision was recorded",
        status: "unknown", source_ids: [] }
    ])
    assert_equal "client_proposal", proposal.kind
    assert_equal "conversation_summary", summary.kind
    assert_equal "unknown", summary.entries.first.status
    assert_equal "pending_manual_review", proposal.review_state
  end

  test "H4 only explicit actor review can mark an entry confirmed" do
    initial = draft
    reviewed = AiWorkspace::StructuredDeliverableV1.review!(
      document: initial, entry_id: 1, actor_id: 4, decision: "confirm"
    )
    assert_equal "confirmed", reviewed.entries.first.status
    assert_equal 4, reviewed.entries.first.reviewed_by_actor_id
    assert_equal "inferred", initial.entries.first.status
    assert_equal "pending_manual_review", reviewed.review_state
    complete = AiWorkspace::StructuredDeliverableV1.review!(
      document: reviewed, entry_id: 2, actor_id: 4,
      decision: "request_confirmation"
    )
    assert_equal "reviewed_not_approved", complete.review_state
    assert_equal "needs_confirmation", complete.entries.last.status
    assert_equal [29], complete.entries.first.source_ids
    assert complete.frozen?

    assert_raises(AiWorkspace::Errors::Unauthorized) do
      AiWorkspace::StructuredDeliverableV1.review!(
        document: initial, entry_id: 1, actor_id: 77, decision: "confirm"
      )
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::StructuredDeliverableV1.review!(
        document: initial, entry_id: 999, actor_id: 4, decision: "confirm"
      )
    end
  end

  test "H4 draft cannot import confirmed, unknown type or unauthorized IDs" do
    invalid_entries = [
      { section: "requirements", text: "It's verified [M29]",
        status: "confirmed", source_ids: [29] },
      { section: "requirements", text: "External [M999]",
        status: "inferred", source_ids: [999] },
      { section: "requirements", text: "Citation from another item [M30]",
        status: "inferred", source_ids: [29] },
      { section: "requirements", text: "Forged [Mabc]",
        status: "inferred", source_ids: [29] },
      { section: "requirements", text: "Overlong [M" + ("9" * 80) + "]",
        status: "inferred", source_ids: [29] },
      { section: "requirements", text: "Unclosed [M29",
        status: "inferred", source_ids: [29] },
      { section: "requirements", text: "Uncited inference",
        status: "inferred", source_ids: [] },
      { section: "not_a_section", text: "Some text",
        status: "unknown", source_ids: [] }
    ]
    invalid_entries.each do |entry|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        draft(entries: [entry])
      end
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      draft(kind: "arbitrary", entries: [])
    end
  end

  test "H4 rejects oversized data, mutable duplicates and invalid bundles" do
    bad = { section: "requirements", text: "x" * 601,
      status: "unknown", source_ids: [] }
    assert_raises(AiWorkspace::Errors::InvalidSelection) { draft(entries: [bad]) }
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      draft(entries: Array.new(37) do
        { section: "requirements", text: "One", status: "inferred", source_ids: [29] }
      end)
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      draft(entries: [{ section: "requirements", text: "Repeated",
        status: "inferred", source_ids: [29, 29] }])
    end
    mismatched = AiWorkspace::ReplyContextBuilder::Bundle.new(
      **bundle.to_h.merge(source_ids: [29, 999])
    )
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      draft(source: mismatched)
    end
  end

  test "H4 has no storage, provider, message or approval side effects" do
    before = Message.count
    document = draft
    AiWorkspace::StructuredDeliverableV1.review!(
      document: document, entry_id: 1, actor_id: 4, decision: "keep_inferred"
    )
    assert_equal before, Message.count
    assert_equal "pending_manual_review", document.review_state
  end
end
