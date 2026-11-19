require "test_helper"

class AiWorkspaceDraftProvenanceTest < ActiveSupport::TestCase
  test "proof is room and author scoped, expires and detects altered source" do
    actor = users(:one)
    room = rooms(:one)
    source = "AI generated text"
    token = AiWorkspace::DraftProvenance.issue(actor: actor, room: room, source_text: source)
    assert AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: room, source_text: source)
    assert_not AiWorkspace::DraftProvenance.valid?(
      token: token, actor: users(:two), room: room, source_text: source)
    assert_not AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: rooms(:two), source_text: source)
    assert_not AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: room, source_text: source + "!")
    assert_not AiWorkspace::DraftProvenance.valid?(
      token: "invalid", actor: actor, room: room, source_text: source)
    travel_to 31.minutes.from_now do
      assert_not AiWorkspace::DraftProvenance.valid?(
        token: token, actor: actor, room: room, source_text: source)
    end
  end
end
