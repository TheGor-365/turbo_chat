require "test_helper"

class AiWorkspaceAutomaticClientBriefV1Test < ActiveSupport::TestCase
  def bundle
    rows = [
      [22, "you", "hey"],
      [29, "you", "Investigate HTTP 422 in Rails and propose a fix."],
      [30, "you", "Investigate HTTP 422 in Rails and propose a fix."],
      [31, "participant_1", "What exact Rails validation errors are shown?"],
      [32, "you", "**Client Brief** **Objective** Diagnose 422 **Requirements** Inspect logs"]
    ].map do |id, speaker, body|
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: id, speaker: speaker, text: body.freeze, truncated: false
      ).freeze
    end
    AiWorkspace::ReplyContextBuilder::Bundle.new(version: 1,
      room_id: 3, actor_id: 4, rows: rows.freeze,
      source_ids: rows.map(&:message_id).freeze,
      characters: rows.sum { |row| row.text.length }, omitted: 0).freeze
  end

  test "automatic client brief excludes greetings repeats and AI recycled briefs" do
    result = AiWorkspace::AutomaticClientBriefV1.build!(bundle: bundle)
    assert_equal "client_brief", result.kind
    assert_equal [29, 31], result.source_ids
    assert_includes result.text, "## Objective"
    assert_includes result.text, "## Requirements"
    assert_includes result.text, "## Constraints"
    assert_includes result.text, "## Deliverables"
    assert_includes result.text, "## Acceptance Criteria"
    assert_includes result.text, "## Open Questions"
    assert_includes result.text, "[M29]"
    assert_includes result.text, "[M31]"
    assert_not_includes result.text, "[M32]"
    assert_not_includes result.text, "[M22]"
    assert_includes result.text, "Reported request (not agreed)"
    assert_includes result.text, "Budget and deadline: To confirm"
    doc = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: result.text, kind: result.kind, bundle: bundle
    )
    assert doc.entries.any? { |entry| entry.status == "inferred" }
    assert doc.entries.any? { |entry| entry.status == "needs_confirmation" }
    assert doc.entries.all? { |entry| entry.reviewed_by_actor_id.nil? }
  end

  test "cannot invent an objective from questions or greetings alone" do
    original = bundle
    rows = original.rows.select { |row| [22, 31].include?(row.message_id) }
    b = original.dup
    b.rows = rows.freeze
    b.source_ids = rows.map(&:message_id).freeze
    b.freeze
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::AutomaticClientBriefV1.build!(bundle: b)
    end
  end
end
