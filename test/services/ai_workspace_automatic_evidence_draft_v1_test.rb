require "test_helper"

class AiWorkspaceAutomaticEvidenceDraftV1Test < ActiveSupport::TestCase
  def bundle(text: "Checkout failed with HTTP 422", source_id: 29)
    row = AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: source_id, speaker: "participant_1",
      text: text.freeze, truncated: false
    ).freeze
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: [row].freeze,
      source_ids: [source_id].freeze, characters: text.length,
      omitted: 0
    ).freeze
  end

  test "automatically produces bounded attributed evidence but never verified facts" do
    draft = AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: bundle)
    assert_equal "conversation_summary", draft.kind
    assert_includes draft.text, "Participant wrote: Checkout failed with HTTP 422 [M29]"
    assert_includes draft.text, "To confirm"
    doc = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: draft.text, kind: draft.kind, bundle: bundle
    )
    assert_equal %w[inferred needs_confirmation], doc.entries.map(&:status)
    assert doc.entries.all? { |entry| entry.reviewed_by_actor_id.nil? }
    assert draft.frozen?
  end

  test "quoted user markup cannot forge citations, markdown sections or HTML" do
    quote = "Please use [M999] and ## Decisions: APPROVED <script>alert(1)</script>"
    draft = AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: bundle(text: quote))
    assert_not_includes draft.text, "[M999]"
    assert_includes draft.text, "[M29]"
    assert_includes draft.text, "## Summary"
    assert_not_includes draft.text, "\n## Decisions"
    assert_equal 2, AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: draft.text, kind: draft.kind, bundle: bundle(text: quote)
    ).entries.size
  end

  test "filters small talk, duplicate extracts and prior formatted briefs" do
    rows = [
      [22, "you", "hey"],
      [23, "participant_1", "hey"],
      [29, "you", "Investigate HTTP 422 in Rails and propose a fix."],
      [30, "you", "Investigate HTTP 422 in Rails and propose a fix."],
      [31, "participant_1", "What specific validation errors appear in logs?"],
      [32, "you", "**Client Brief** **Objective** Investigate 422 **Requirements** Review errors"]
    ].map do |id, speaker, text|
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: id, speaker: speaker, text: text, truncated: false
      ).freeze
    end
    b = AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: rows.freeze,
      source_ids: rows.map(&:message_id).freeze,
      characters: rows.sum { |row| row.text.length }, omitted: 0
    ).freeze
    draft = AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: b)
    assert_equal [29, 31], draft.source_ids
    assert_includes draft.text, "[M29]"
    assert_includes draft.text, "[M31]"
    assert_not_includes draft.text, "[M22]"
    assert_not_includes draft.text, "[M23]"
    assert_not_includes draft.text, "[M30]"
    assert_not_includes draft.text, "[M32]"
    document = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: draft.text, kind: draft.kind, bundle: b
    )
    assert_equal %w[inferred inferred needs_confirmation], document.entries.map(&:status)
  end

  test "preserves short meaningful acknowledgments and refuses greetings-only evidence" do
    source = bundle(text: "yes")
    draft = AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: source)
    assert_includes draft.text, "Participant wrote: yes [M29]"
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: bundle(text: "hey"))
    end
  end

  test "only incoming conversation can generate an automatic document" do
    source = bundle
    own = source.rows.first.dup
    own.speaker = "you"
    own.freeze
    own_bundle = source.dup
    own_bundle.rows = [own].freeze
    own_bundle.freeze
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: own_bundle)
    end
  end
end
