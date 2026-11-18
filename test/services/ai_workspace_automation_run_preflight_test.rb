require "test_helper"

class AiAutomationRunPreflightTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob, body: "Confirm Rails validations")
    @policy = AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "review", summary_mode: "after_messages")
    @goal = AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Understand the issue")
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    @registry = AiWorkspace::AutomationRunRegistry.new
    @gate = AiWorkspace::AutomationRunPreflight.new
  end

  test "unchanged Apply metadata is current but NEVER authorizes execution" do
    run = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    before = AiAutomationRun.count
    result = @gate.check!(run: run)
    assert result.current
    assert_equal false, result.execution_authorized
    assert_equal [@incoming.id], result.source_message_ids
    assert_equal before, AiAutomationRun.count
    assert_equal 1, @room.messages.count
    assert_equal 0, AiDeliverable.count
  end

  test "editing source, changing goal, changing policy or canceling run invalidates it" do
    run = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    @incoming.update!(body: "Now a different error")
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @gate.check!(run: run) }

    fresh = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    @goal.update!(revision: 2)
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @gate.check!(run: fresh) }

    new_goal = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    @policy.update!(revision: 2)
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @gate.check!(run: new_goal) }

    current = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    current.update!(status: "canceled", cancellation_reason: "policy_disabled",
      canceled_at: Time.current)
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @gate.check!(run: current) }
  end

  test "revoked consent or departed member makes previously recorded event unusable" do
    run = @registry.capture_incoming!(room: @room, actor: @alice, incoming: @incoming)
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) { @gate.check!(run: run) }

    AiRoomContextConsent.find_by!(room: @room, user: @bob).grant!
    @room.participants.where(user: @bob).delete_all
    assert_raises(AiWorkspace::Errors::ConsentRequired) { @gate.check!(run: run) }
  end

  test "outcome snapshots are invalidated by newer conversation evidence" do
    run = @registry.capture_outcome!(room: @room, actor: @alice,
      window_key: "after_messages:#{@incoming.id}")
    assert_equal false, @gate.check!(run: run).execution_authorized
    @room.messages.create!(user: @bob, body: "The deadline is not agreed")
    assert_raises(AiWorkspace::Errors::InvalidSelection) { @gate.check!(run: run) }
    assert_equal 0, AiDeliverable.count
  end
end
