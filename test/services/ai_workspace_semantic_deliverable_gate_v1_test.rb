require "test_helper"

class AiWorkspaceSemanticDeliverableGateV1Test < ActiveSupport::TestCase
  def bundle
    row = AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: 29, speaker: "participant_1", text: "Checkout returned HTTP 422",
      truncated: false
    ).freeze
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: [row].freeze,
      source_ids: [29].freeze, characters: 26, omitted: 0
    ).freeze
  end

  def complete_brief
    [
      "## Objective", "- Investigate 422 [M29]",
      "## Requirements", "- Inspect validation failures [M29]",
      "## Constraints", "- Technical constraints: To confirm",
      "## Deliverables", "- Exact deliverables: To confirm",
      "## Acceptance Criteria", "- Acceptance: To confirm",
      "## Open Questions", "- Deadline and budget: To confirm"
    ].join("\n")
  end

  test "accepts structurally complete grounded draft without marking it approved" do
    result = AiWorkspace::SemanticDeliverableGateV1.inspect!(
      text: complete_brief, kind: "client_brief", bundle: bundle
    )
    assert result.complete
    assert_empty result.warnings
    assert_equal "pending_manual_review", result.document.review_state
    assert_equal %w[inferred inferred needs_confirmation needs_confirmation needs_confirmation needs_confirmation],
      result.document.entries.map(&:status)
    assert result.document.entries.all? { |row| row.reviewed_by_actor_id.nil? }
    assert result.frozen?
  end

  test "missing sections become warnings instead of invented content" do
    result = AiWorkspace::SemanticDeliverableGateV1.inspect!(
      text: "## Objective\n- Investigate 422 [M29]",
      kind: "client_brief", bundle: bundle
    )
    refute result.complete
    assert result.warnings.any? { |s| s.include?("Missing section: requirements") }
  end

  test "model-written agreement claim never counts as human verification" do
    text = complete_brief.sub("Investigate 422 [M29]", "Approved scope is final [M29]")
    result = AiWorkspace::SemanticDeliverableGateV1.inspect!(
      text: text, kind: "client_brief", bundle: bundle
    )
    refute result.complete
    assert result.warnings.any? { |s| s.include?("Possible agreement claim") }
    assert_equal "inferred", result.document.entries.first.status
  end

  test "explicit absence of agreement is not misreported as an approved scope" do
    draft = complete_brief.sub("Technical constraints: To confirm",
      "No agreed timeline or cost yet [M29]")
    result = AiWorkspace::SemanticDeliverableGateV1.inspect!(
      text: draft, kind: "client_brief", bundle: bundle
    )
    assert result.complete
    assert_empty result.warnings
    assert_equal "inferred", result.document.entries.find { |item|
      item.text.include?("No agreed timeline")
    }.status
  end

  test "unnegated agreement still requires human review" do
    draft = complete_brief.sub("Technical constraints: To confirm",
      "Timeline and cost agreed [M29]")
    result = AiWorkspace::SemanticDeliverableGateV1.inspect!(
      text: draft, kind: "client_brief", bundle: bundle
    )
    refute result.complete
    assert result.warnings.any? { |warning| warning.include?("Possible agreement claim") }
  end

  test "rejects forged IDs, unclosed citations, unsupported kind and unstructured output" do
    samples = [
      ["client_brief", complete_brief.sub("[M29]", "[M999]")],
      ["client_brief", complete_brief.sub("[M29]", "[M29")],
      ["client_brief", "AI says this requirement is approved"],
      ["arbitrary", complete_brief]
    ]
    samples.each do |kind, text|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        AiWorkspace::SemanticDeliverableGateV1.inspect!(
          text: text, kind: kind, bundle: bundle
        )
      end
    end
  end
end
