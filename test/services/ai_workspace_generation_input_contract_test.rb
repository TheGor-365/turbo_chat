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
    assert_equal "M#{@incoming.id}", data.fetch("reply_to_ref")
    refute_includes compiled.system_instruction, "Ask the client"
    assert_includes compiled.system_instruction, "lower-trust"
    assert_includes compiled.system_instruction, "writing_preferences.language"
    assert_includes compiled.system_instruction, "writing_preferences.tone"
    assert_includes compiled.system_instruction, "Preserve code"
    assert_equal false, compiled.provider_called
    assert_equal false, compiled.message_sent
    assert compiled.frozen?
    assert compiled.user_content.frozen?
    assert_equal 1, @room.messages.count
  end

  test "compiled answer targets latest included incoming message rather than older issue" do
    enable_answer
    @incoming.update!(body: "POST /orders returns 422. Need validation details.")
    latest = @room.messages.create!(user: @bob,
      body: "Please send the landing page assets and confirm who approves them.")
    @room.messages.create!(user: @alice, body: "I can review the content before agreeing.")
    req = request(mode: "answer", expected_goal_revision: 2)
    plan = @planner.prepare(request: req)
    compiled = AiWorkspace::GenerationInputContract.build!(plan: plan, request: req)
    data = JSON.parse(compiled.user_content)
    assert_equal "M#{latest.id}", data.fetch("reply_to_ref")
    assert_includes compiled.source_ids, @incoming.id
    assert_includes compiled.source_ids, latest.id
    assert_includes compiled.system_instruction, "payload.reply_to_ref"
    assert_equal false, compiled.message_sent
  end

  test "chosen older incoming target and signed source subset survive review and Send proof" do
    enable_answer
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 2, content: "Ask for acceptance criteria only.")
    @incoming.update!(body: "Original Rails scope was limited to registration.")
    latest = @room.messages.create!(user: @bob,
      body: "Please send the new landing page assets tomorrow.")
    @room.messages.create!(user: @alice, body: "I will check what is available.")
    initial = request(mode: "answer", expected_goal_revision: 2,
      goal_source: "room_instructions")
    full = @planner.prepare(request: initial).prepared
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: full, hint: "")
    ids = [@incoming.id, latest.id]
    chosen = request(mode: "answer", expected_goal_revision: 2,
      goal_source: "room_instructions", source_token: token, selected_ids: ids, reply_target_id: @incoming.id)
    compiled = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: chosen), request: chosen)
    data = JSON.parse(compiled.user_content)
    assert_equal "M#{@incoming.id}", data.fetch("reply_to_ref")
    assert_equal ids, compiled.source_ids
    assert_not_includes data.fetch("excerpts").map { |row| row.fetch("text") },
      "I will check what is available."

    proof = AiWorkspace::DraftProvenance.issue(actor: @alice, room: @room,
      source_text: "Please clarify the Rails registration acceptance criteria.",
      answer_context: { "request_id" => chosen.request_id,
        "goal_revision" => 2, "fingerprint" => compiled.fingerprint,
        "source_token" => token, "selected_ids" => ids,
        "reply_target_id" => @incoming.id })
    assert AiWorkspace::DraftProvenance.valid?(token: proof, actor: @alice,
      room: @room, source_text: "Please clarify the Rails registration acceptance criteria.")

    @incoming.update!(body: "The scope has been changed.")
    assert_not AiWorkspace::DraftProvenance.valid?(token: proof, actor: @alice,
      room: @room, source_text: "Please clarify the Rails registration acceptance criteria.")
  end

  test "selected target must be an included incoming participant message" do
    enable_answer
    author = @room.messages.create!(user: @alice, body: "My unsent notes.")
    base = request(mode: "answer", expected_goal_revision: 2)
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: @planner.prepare(request: base).prepared, hint: "")
    [author.id, 987_654_321].each do |bad_target|
      chosen = request(mode: "answer", expected_goal_revision: 2,
        source_token: token, selected_ids: [@incoming.id, author.id],
        reply_target_id: bad_target)
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        @planner.prepare(request: chosen)
      end
    end
    assert_equal 0, AiUsageReservation.count
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

  test "shared revision invalidates stale fingerprints even after values round trip" do
    @room = Room.create!(name: "Fingerprint shared group", kind: "private_group",
      is_private: true, owner: @alice)
    @room.participants.create!(user: @alice, group_role: "owner")
    @room.participants.create!(user: @bob, group_role: "member")
    @incoming = @room.messages.create!(user: @bob,
      body: "Please clarify the Rails form acceptance criteria.")
    enable_answer
    service = AiWorkspace::SharedWritingPreferences
    baseline = { profile_id: "universal", writing_style: "polish_clarity",
      language: "en", tone: "neutral" }
    service.write(room: @room, actor: @alice, attributes: baseline, expected_revision: 0)
    req = request(mode: "answer", expected_goal_revision: 2)
    first = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)
    service.write(room: @room, actor: @alice,
      attributes: baseline.merge(language: "hy"), expected_revision: 1)
    changed = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)
    service.write(room: @room, actor: @alice, attributes: baseline, expected_revision: 2)
    restored = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)

    assert_not_equal first.fingerprint, changed.fingerprint
    assert_equal first.user_content, restored.user_content
    assert_not_equal first.fingerprint, restored.fingerprint
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count

    # A fully personalized room snapshot does not inherit later shared edits.
    AiRoomWritingPreference.create!(user: @alice, room: @room, **baseline)
    personal = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)
    service.write(room: @room, actor: @alice,
      attributes: baseline.merge(language: "ru"), expected_revision: 3)
    personal_after_shared_edit = AiWorkspace::GenerationInputContract.build!(
      plan: @planner.prepare(request: req), request: req)
    assert_equal personal.fingerprint, personal_after_shared_edit.fingerprint
  end
end
