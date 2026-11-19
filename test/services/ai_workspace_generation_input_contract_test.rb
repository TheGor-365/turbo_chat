require "test_helper"
require "securerandom"
require "json"

class AiWorkspaceGenerationInputContractTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Which Rails signup form should we fix?")
    @planner = AiWorkspace::GenerationOrchestrator.new
  end

  def request(mode:, draft: "", **opts)
    AiWorkspace::GenerationOrchestrator::Request.new(
      actor: @alice, room: @room, mode: mode, request_id: SecureRandom.uuid,
      draft_text: draft, confirmed: "1", **opts)
  end

  def enable_answer
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Ask the client for precise acceptance criteria",
      constraints: "No invented delivery date",
      desired_outcome: "Agree on form validation steps",
      revision: 2, active: true)
  end

  test "answer compiles goal as untrusted user content and only permitted excerpts" do
    enable_answer
    req = request(mode: "answer", expected_goal_revision: 2)
    plan = @planner.prepare(request: req)
    compiled = AiWorkspace::GenerationInputContract.build!(plan: plan, request: req)
    data = JSON.parse(compiled.user_content)
    assert_equal "answer", compiled.mode
    assert_equal [@incoming.id], compiled.source_ids
    assert_equal 2, compiled.goal_revision
    assert_equal "Ask the client for precise acceptance criteria", data.dig("personal_goal", "purpose")
    assert_equal "Which Rails signup form should we fix?", data.fetch("excerpts").sole.fetch("text")
    refute_includes compiled.system_instruction, "Ask the client"
    assert_includes compiled.system_instruction, "lower-trust"
    assert_equal false, compiled.provider_called
    assert_equal false, compiled.message_sent
    assert compiled.frozen?
    assert compiled.user_content.frozen?
    assert_equal 1, @room.messages.count
  end

  test "beautify compiles only the human draft, not the private room history or goal" do
    req = request(mode: "beautify", draft: "pls fix typo in ruby on rails.",
      preset_id: "polish_clarity")
    compiled = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)
    data = JSON.parse(compiled.user_content)
    assert_equal "beautify_own_unsent_draft", data.fetch("task")
    assert_equal "pls fix typo in ruby on rails.", data.fetch("draft")
    assert_nil data["personal_goal"]
    refute_includes compiled.user_content, @incoming.body
    assert_equal [], compiled.source_ids
  end

  test "goal edits, source edits and consent revoke-regrant change fingerprint" do
    enable_answer
    req = request(mode: "answer", expected_goal_revision: 2)
    original = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req).fingerprint
    @incoming.update!(body: "Please fix the mobile Rails signup form")
    altered_source = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req).fingerprint
    assert_not_equal original, altered_source

    grant = AiRoomContextConsent.find_by!(room: @room, user: @bob)
    grant.revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) { @planner.prepare(request: req) }
    grant.grant!
    altered_consent = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req).fingerprint
    assert_not_equal altered_source, altered_consent

    goal = AiConversationGoal.find_by!(room: @room, user: @alice)
    goal.update!(purpose: "Ask one targeted question", revision: 3)
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @planner.prepare(request: req) }
  end

  test "goal containing possible personal email is rejected before any outbound use" do
    enable_answer
    AiConversationGoal.find_by!(room: @room, user: @alice)
      .update!(constraints: "Send response to private@example.com")
    req = request(mode: "answer", expected_goal_revision: 2)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::GenerationInputContract.build!(
        plan: @planner.prepare(request: req), request: req)
    end
  end

  test "auto_reply remains fail closed without compiled input" do
    enable_answer
    req = request(mode: "auto_reply", expected_goal_revision: 2)
    assert_raises(AiWorkspace::Errors::ProviderUnavailable) { @planner.prepare(request: req) }
  end
end
