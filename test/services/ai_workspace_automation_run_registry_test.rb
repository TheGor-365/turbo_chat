require "test_helper"

class AiAutomationRunRegistryTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Please check the Rails signup issue")
    @policy = AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "review", summary_mode: "after_messages",
      summary_kind: "conversation_summary")
    @goal = AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Help with Rails registration", revision: 1)
    @registry = AiWorkspace::AutomationRunRegistry.new
  end

  def grant_all
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
  end

  test "Apply-mode event capture is idempotent, durable and never sends or generates" do
    grant_all
    first = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    again = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    assert_equal first.id, again.id
    assert_equal 1, AiAutomationRun.count
    assert_equal "reply_proposal", first.run_kind
    assert_equal "recorded", first.status
    assert_equal [@incoming.id], first.source_message_ids
    assert_equal 64, first.event_key.size
    assert_equal 64, first.source_fingerprint.size
    assert_equal 1, first.policy_revision
    assert_equal @goal.revision, first.goal_revision
    assert_equal 1, @room.messages.count
    assert_equal 0, AiDeliverable.count
    assert_not_includes first.attributes.inspect, @incoming.body
    assert_not_includes first.attributes.inspect, @goal.purpose
  end

  test "full-auto setting only stages non-executable metadata" do
    grant_all
    @policy.update!(reply_mode: "full_auto", revision: 2)
    event = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    assert_equal "reply_unattended", event.run_kind
    assert_equal "recorded", event.status
    assert_equal 0, @room.messages.where(user: @alice).count
    assert_not event.respond_to?(:send!)
  end

  test "message edit and goal revision create different fingerprints" do
    grant_all
    first = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    @incoming.update!(body: "Please review signup validation 422")
    second = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    assert_not_equal first.id, second.id
    assert_not_equal first.source_fingerprint, second.source_fingerprint
    @goal.update!(revision: 2)
    third = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    assert_not_equal second.id, third.id
    assert_equal 3, AiAutomationRun.count
  end

  test "summary windows dedupe and store source references without provider calls" do
    grant_all
    first = @registry.capture_outcome!(room: @room, actor: @alice,
      window_key: "after_messages:#{@incoming.id}")
    again = @registry.capture_outcome!(room: @room, actor: @alice,
      window_key: "after_messages:#{@incoming.id}")
    assert_equal first.id, again.id
    assert_equal "conversation_outcome", first.run_kind
    assert_equal [@incoming.id], first.source_message_ids
    assert_nil first.trigger_message_id
    assert_equal 0, AiDeliverable.count
    assert_equal 1, @room.messages.count
    assert_equal 1, AiAutomationRun.count
  end

  test "invalid scopes, mode, own message and missing goal are rejected" do
    grant_all
    own = @room.messages.create!(user: @alice, body: "My reply")
    assert_raises(AiWorkspace::AutomationRunRegistry::Unavailable) do
      @registry.capture_incoming!(room: @room, actor: @alice, incoming: own)
    end
    assert_raises(AiWorkspace::AutomationRunRegistry::Unavailable) do
      @registry.capture_outcome!(room: @room, actor: @alice,
        window_key: "daily:2026-11-18")
    end
    @policy.update!(reply_mode: "off", summary_mode: "off", revision: 2)
    assert_raises(AiWorkspace::AutomationRunRegistry::Unavailable) do
      @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    end
    assert_raises(AiWorkspace::AutomationRunRegistry::Unavailable) do
      @registry.capture_outcome!(room: @room, actor: @alice, window_key: "after_messages:10")
    end
    @policy.update!(reply_mode: "review", revision: 3)
    @goal.update!(active: false, revision: 2)
    assert_raises(AiWorkspace::AutomationRunRegistry::Unavailable) do
      @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    end
    assert_equal 0, AiAutomationRun.count
  end

  test "missing participant consent or departed author blocks staging" do
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    end
    grant_all
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @registry.capture_outcome!(room: @room, actor: @alice, window_key: "after_messages:10")
    end
    grant_all
    @room.participants.where(user: @bob).delete_all
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    end
    assert_equal 0, AiAutomationRun.count
  end

  test "policy changes invalidate earlier recorded events without deleting audit" do
    grant_all
    run = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    @room.with_lock do
      @policy.update!(reply_mode: "off", summary_mode: "off", revision: 2)
      count = AiAutomationRun.cancel_obsolete!(room: @room, user: @alice,
        current_revision: @policy.revision, reason: "policy_disabled")
      assert_equal 1, count
    end
    assert_equal "canceled", run.reload.status
    assert_equal "policy_disabled", run.cancellation_reason
    assert run.canceled_at.present?
    assert_equal 1, AiAutomationRun.count
    assert_equal 1, @room.messages.count
    assert_equal 0, AiDeliverable.count
  end
end
