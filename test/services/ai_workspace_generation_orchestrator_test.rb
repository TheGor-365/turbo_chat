require "test_helper"
require "securerandom"

class AiWorkspaceGenerationOrchestratorTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Could you explain which Rails form needs fixing?")
    @service = AiWorkspace::GenerationOrchestrator.new
  end

  def request(mode:, draft: "", **extra)
    AiWorkspace::GenerationOrchestrator::Request.new(
      mode: mode, actor: @alice, room: @room, draft_text: draft,
      request_id: SecureRandom.uuid, confirmed: "1", **extra)
  end

  def grant_context
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def create_goal
    AiConversationGoal.create!(user: @alice, room: @room,
      purpose: "Clarify the requested implementation", revision: 2, active: true)
  end

  test "beautify prepares a safe own draft without billing, provider or Send" do
    original_messages = Message.count
    prepared = @service.prepare(request: request(mode: "beautify",
      draft: "Please clarify the expected form behavior.", preset_id: "polish_clarity"))
    assert_equal "beautify", prepared.mode
    assert_equal "own_draft", prepared.source
    assert_equal [], prepared.source_ids
    assert_equal "own_draft", prepared.prepared.source
    assert_equal false, prepared.provider_called
    assert_equal false, prepared.budget_reserved
    assert_equal false, prepared.message_sent
    assert_equal original_messages, Message.count
    assert prepared.frozen?
  end

  test "answer uses only a current personal goal and unanimous permitted bounded context" do
    grant_context
    create_goal
    original_messages = Message.count
    prepared = @service.prepare(request: request(mode: "answer",
      expected_goal_revision: 2))
    assert_equal "answer", prepared.mode
    assert_equal "bounded_room_context", prepared.source
    assert_equal [@incoming.id], prepared.source_ids
    assert_equal 2, prepared.goal_snapshot.fetch(:revision)
    assert_equal "Clarify the requested implementation", prepared.goal_snapshot.fetch(:purpose)
    assert_equal @alice.id, prepared.actor_id
    assert_equal @room.id, prepared.room_id
    assert_equal false, prepared.provider_called
    assert_equal false, prepared.budget_reserved
    assert_equal false, prepared.message_sent
    assert_equal original_messages, Message.count
  end

  test "missing peer consent and stale personal goal never create a generation plan" do
    create_goal
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @service.prepare(request: request(mode: "answer", expected_goal_revision: 2))
    end
    grant_context
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.prepare(request: request(mode: "answer", expected_goal_revision: 1))
    end
  end

  test "unsupported and unattended modes, unconfirmed or mismatched editor states fail closed" do
    bad = [
      request(mode: "auto_reply", expected_goal_revision: 1),
      request(mode: "unrestricted"),
      request(mode: "beautify", draft: "", preset_id: "polish_clarity"),
      request(mode: "beautify", draft: "Human draft", preset_id: "polish_clarity", confirmed: "0"),
      request(mode: "answer", draft: "Must not be overwritten", expected_goal_revision: 1)
    ]
    bad.each do |entry|
      assert_raises(AiWorkspace::Errors::InvalidSelection,
        AiWorkspace::Errors::ConsentRequired,
        AiWorkspace::Errors::ProviderUnavailable) do
        @service.prepare(request: entry)
      end
    end
    assert_equal 1, @room.messages.count
  end

  test "source review receipt becomes invalid when an incoming message changes" do
    grant_context
    create_goal
    bundle = AiWorkspace::ReplyContextBuilder.new.build(room: @room, actor: @alice)
    token = AiWorkspace::SourceSelection.issue(room: @room, actor: @alice,
      bundle: bundle, hint: "")
    @incoming.update!(body: "The incoming request has been materially corrected.")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.prepare(request: request(mode: "answer", expected_goal_revision: 2,
        source_token: token, selected_ids: [@incoming.id]))
    end
  end
end
