require "test_helper"

class AiWorkspaceStructuredDeliverableComparisonV1Test < ActiveSupport::TestCase
  def bundle(room_id: 3, actor_id: 4)
    row = AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: 29, speaker: "participant_1", text: "Rails 422", truncated: false
    ).freeze
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: room_id, actor_id: actor_id, rows: [row].freeze,
      source_ids: [29].freeze, characters: 9, omitted: 0
    ).freeze
  end

  def doc(text, room_id: 3, actor_id: 4)
    AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: text, kind: "client_brief", bundle: bundle(room_id: room_id, actor_id: actor_id)
    )
  end

  test "compares exact duplicates occurrence by occurrence" do
    original = doc("## Requirements\n- Same [M29]\n- Same [M29]\n- Removed")
    proposed = doc("## Requirements\n- Same [M29]\n- Added")
    result = AiWorkspace::StructuredDeliverableComparisonV1.compare!(
      original: original, proposed: proposed
    )
    assert_equal ["Same [M29]"], result.unchanged.map(&:text)
    assert_equal ["Same [M29]", "Removed"], result.removed.map(&:text)
    assert_equal ["Added"], result.added.map(&:text)
    assert result.frozen?
    assert_equal "pending_manual_review", proposed.review_state
  end

  test "changed source reference is not equal and status never carries over" do
    original = doc("## Requirements\n- Same [M29]")
    proposed = doc("## Open Questions\n- Same [M29]")
    result = AiWorkspace::StructuredDeliverableComparisonV1.compare!(
      original: original, proposed: proposed
    )
    assert_empty result.unchanged
    assert_equal 1, result.added.size
    assert_equal 1, result.removed.size
    assert_nil result.added.first.reviewed_by_actor_id
  end

  test "rejects mismatched actor or room even with the same text" do
    original = doc("## Requirements\n- Check [M29]")
    [doc("## Requirements\n- Check [M29]", room_id: 7),
      doc("## Requirements\n- Check [M29]", actor_id: 8)].each do |other|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        AiWorkspace::StructuredDeliverableComparisonV1.compare!(
          original: original, proposed: other
        )
      end
    end
  end
end
