require "test_helper"

class AiWorkspaceReplyOutputGuardTest < ActiveSupport::TestCase
  def bundle(text)
    AiWorkspace::ReplyContextBuilder::Bundle.new(version: 1, room_id: 123,
      actor_id: 456,
      rows: [
        AiWorkspace::ReplyContextBuilder::Row.new(
          message_id: 789, speaker: "participant_2", text: text,
          truncated: false
        )
      ], source_ids: [789], characters: text.length, omitted: 0)
  end

  test "allows plain, context-grounded reply and documented URL or amount" do
    data = bundle("Please review https://example.test/brief and budget $1200.")
    assert AiWorkspace::ReplyOutputGuard.validate!(
      text: "I can review https://example.test/brief with a budget of $1200.",
      bundle: data, hint: "")
    assert AiWorkspace::ReplyOutputGuard.validate!(
      text: "Could you clarify the agreed deadline?", bundle: data, hint: "")
  end

  test "blocks newly invented dates, money, URLs and personal addresses" do
    data = bundle("Please review the draft today.")
    ["It costs $500.", "Use https://made-up.test/", "Due 2026-11-11.",
      "Contact fake@example.test"].each do |invented|
      assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
        AiWorkspace::ReplyOutputGuard.validate!(text: invented, bundle: data, hint: "")
      end
    end
  end
end
