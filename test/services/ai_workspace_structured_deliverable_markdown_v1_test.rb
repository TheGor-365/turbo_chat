require "test_helper"

class AiWorkspaceStructuredDeliverableMarkdownV1Test < ActiveSupport::TestCase
  def bundle
    rows = [
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: 29, speaker: "participant_1", text: "Rails checkout returned 422", truncated: false
      ).freeze
    ]
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: rows.freeze,
      source_ids: [29].freeze, characters: 27, omitted: 0
    ).freeze
  end

  def parse(text, kind: "client_brief")
    AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: text, kind: kind, bundle: bundle
    )
  end

  test "cited claims remain inferred rather than confirmed" do
    result = parse("## Requirements\n- Investigate checkout 422 [M29]\n" \
      "## Open questions\n- Deadline: To confirm")
    assert_equal %w[inferred needs_confirmation], result.entries.map(&:status)
    assert_equal [29], result.entries.first.source_ids
    assert_equal [], result.entries.last.source_ids
    assert_equal "pending_manual_review", result.review_state
    assert result.frozen?
  end

  test "sourceless factual claims require confirmation" do
    result = parse("## Objective\n- Launch by Friday")
    assert_equal "needs_confirmation", result.entries.first.status
    assert_empty result.entries.first.source_ids
  end

  test "proposal and summary are typed separately" do
    proposal = parse("## Assumptions\n- Additional diagnostics [M29]",
      kind: "client_proposal")
    summary = parse("## Decisions\n- No decision confirmed",
      kind: "conversation_summary")
    assert_equal "assumptions", proposal.entries.first.section
    assert_equal "decisions", summary.entries.first.section
    assert_equal "needs_confirmation", summary.entries.first.status
  end

  test "forged, malformed, outsider and unclosed citations are rejected" do
    ["[M999]", "[Mabc]", "[M0]", "[M29", "[M999999999999999999999]"].each do |tag|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        parse("## Requirements\n- Check #{tag}")
      end
    end
  end

  test "unstructured and code content are rejected rather than guessed" do
    ["- Standalone item", "## Not a section\n- text",
      "## Requirements\nraw paragraph", "## Requirements\n```ruby",
      "## Requirements\n| table |"].each do |body|
      assert_raises(AiWorkspace::Errors::InvalidSelection) { parse(body) }
    end
  end

  test "bounded document and no message persistence" do
    before = Message.count
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      parse("## Requirements\n" + Array.new(37, "- Check [M29]").join("\n"))
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      parse("## Requirements\n- " + ("X" * 601))
    end
    parse("## Requirements\n- Investigate checkout [M29]")
    assert_equal before, Message.count
  end
end
