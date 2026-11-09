require "test_helper"

class AiWorkspaceOwnDraftPreflightTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @preflight = AiWorkspace::OwnDraftPreflight.new
  end

  test "manual preflight prepares only an authorized author's own draft" do
    prepared = @preflight.prepare(actor: @alice, room: @room,
      draft_text: "Please review this draft.", preset_id: "polish_clarity",
      approved_preview: true)
    assert_equal "own_draft", prepared.source
    assert_equal 1, prepared.rows.size
    assert_nil prepared.rows.first.source_id
    assert_equal "Please review this draft.", prepared.rows.first.text
    assert_not AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!(prepared)
    end
  end

  test "preflight refuses absent or untrusted approval" do
    [false, nil, "true", 1].each do |approved|
      assert_raises(AiWorkspace::Errors::ConsentRequired) do
        @preflight.prepare(actor: @alice, room: @room,
          draft_text: "Own draft", preset_id: "polish_clarity",
          approved_preview: approved)
      end
    end
  end

  test "preflight refuses history and summary presets" do
    assert_raises(AiWorkspace::Errors::InvalidPreset) do
      @preflight.prepare(actor: @alice, room: @room,
        draft_text: "Own draft", preset_id: "technical_summary",
        approved_preview: true)
    end
  end

  test "preflight denies revoked membership even when author confirmed" do
    @room.participants.where(user: @alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @preflight.prepare(actor: @alice, room: @room,
        draft_text: "Own draft", preset_id: "polish_clarity",
        approved_preview: true)
    end
  end

  test "preflight rejects empty oversized and secret-like texts without outbound calls" do
    ["", "x" * 5001].each do |draft|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        @preflight.prepare(actor: @alice, room: @room,
          draft_text: draft, preset_id: "polish_clarity", approved_preview: true)
      end
    end
    prepared = @preflight.prepare(actor: @alice, room: @room,
      draft_text: "Contact me at demo@example.test", preset_id: "polish_clarity",
      approved_preview: true)
    assert_includes prepared.rows.first.warnings, :possible_email
    assert_not AiWorkspace::Gateway.configured?
  end
end
