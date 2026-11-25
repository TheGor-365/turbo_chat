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

  test "signed multiline source remains valid after form CRLF normalization only" do
    actor = users(:one)
    room = rooms(:one)
    source = "[SYNTHETIC TEST]\nA detail that must remain intact."
    token = AiWorkspace::DraftProvenance.issue(
      actor: actor, room: room, source_text: source)
    assert AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: room,
      source_text: source.gsub("\n", "\r\n"))
    refute AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: room,
      source_text: source.sub("intact", "changed"))
    refute AiWorkspace::DraftProvenance.valid?(
      token: token, actor: actor, room: room,
      source_text: source.gsub("\n", "\r"))
  end
  test "verified workflow is derived from signed source, never caller supplied kind" do
    actor = users(:one)
    room = rooms(:one)
    source = "Reviewed own draft"
    token = AiWorkspace::DraftProvenance.issue(actor: actor, room: room, source_text: source)
    args = { token: token, actor: actor, room: room, source_text: source }
    assert_equal "own_draft_edit", AiWorkspace::DraftProvenance.verified_workflow(**args)
    assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args.merge(source_text: source + "!"))
    assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args.merge(actor: users(:two)))
    assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args.merge(room: rooms(:two)))
    assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args.merge(token: "forged"))
    travel_to 31.minutes.from_now do
      assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args)
    end
  end
  test "v2 own draft proof preserves v1 compatibility and rejects inconsistent workflow" do
    actor = users(:one)
    room = rooms(:one)
    args = { actor: actor, room: room, source_text: "A reviewed result" }
    legacy = AiWorkspace::DraftProvenance.issue(**args)
    current = AiWorkspace::DraftProvenance.issue(**args, workflow: "own_draft_edit")
    [legacy, current].each do |token|
      assert AiWorkspace::DraftProvenance.valid?(**args, token: token)
      assert_equal "own_draft_edit", AiWorkspace::DraftProvenance.verified_workflow(**args, token: token)
    end
    %w[manual model_answer synthetic_answer arbitrary].each do |workflow|
      assert_raises(ArgumentError) { AiWorkspace::DraftProvenance.issue(**args, workflow: workflow) }
    end
    assert_nil AiWorkspace::DraftProvenance.verified_workflow(**args.merge(source_text: "Other"), token: current)
  end
end
