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
      "Raw paragraph without heading", "## Requirements\n```ruby",
      "## Requirements\n| table |"].each do |body|
      assert_raises(AiWorkspace::Errors::InvalidSelection) { parse(body) }
    end
  end

  test "legacy generated brief title, plain headings and paragraphs parse without confirmation" do
    text = "Client Brief\nObjective\nDiagnose Rails HTTP 422 [M29]\n" \
      "Requirements\n• Inspect validations [M29]\n- Review strong params [M29]\n" \
      "**Open Questions**\nBudget: To confirm"
    result = parse(text)
    assert_equal %w[objective requirements requirements open_questions],
      result.entries.map(&:section)
    assert_equal %w[inferred inferred inferred needs_confirmation],
      result.entries.map(&:status)
    assert_equal [29], result.entries.first.source_ids
    assert_equal "pending_manual_review", result.review_state
  end

  test "legacy proposal and summary preserve explicit sections" do
    proposal = parse("**Problem**\n422 response [M29]\n" \
      "**Proposed Work**\n- Inspect validations [M29]\n" \
      "Next Steps\nAgree on access", kind: "client_proposal")
    summary = parse("Conversation Summary\nConfirmed Facts\n" \
      "- 422 response [M29]\nDecisions\nNo decision agreed", kind: "conversation_summary")
    assert_equal %w[problem approach next_steps], proposal.entries.map(&:section)
    assert_equal %w[summary decisions], summary.entries.map(&:section)
    assert_equal "inferred", summary.entries.first.status
    assert_equal "needs_confirmation", summary.entries.last.status
  end

  test "legacy parser rejects unsupported explicit headings, forged sources and code" do
    ["## Definitely Unknown\n- Check", "**Unsupported**\n- Check",
      "Requirements\nClaim [M999]", "Requirements\nClaim [M29",
      "Requirements\n\`\`\`ruby", "Client Brief\nUnstructured preface\nRequirements\n- Check"].each do |text|
      assert_raises(AiWorkspace::Errors::InvalidSelection) { parse(text) }
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
