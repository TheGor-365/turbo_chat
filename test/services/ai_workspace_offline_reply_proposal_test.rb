require "test_helper"

class AiWorkspaceOfflineReplyProposalTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Please review Rails signup validations")
    @policy = AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "review")
    @goal = AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Clarify scope", revision: 1)
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
      AiRoomAutomationConsent.create!(room: @room, user: user,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true)
    end
    @service = AiWorkspace::OfflineReplyProposal.new
  end

  test "one incoming event creates one persistent candidate, never a model call or Send" do
    first = @service.create!(room: @room, actor: @alice)
    again = @service.create!(room: @room, actor: @alice)
    assert_equal first.id, again.id
    assert_equal "offline_template", first.origin
    assert_equal "reply_proposal", first.ai_automation_run.run_kind
    assert_equal @incoming.id, first.ai_automation_run.trigger_message_id
    assert_equal false, first.snapshot.fetch(:ai_assisted)
    assert_equal false, first.snapshot.fetch(:provider_called)
    assert_equal 1, AiReplyProposal.count
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count
  end

  test "Apply is idempotent, saves a decision but never Sends" do
    item = @service.create!(room: @room, actor: @alice, language: "ru")
    assert_equal "applied", @service.apply!(proposal: item, actor: @alice).state
    assert_equal "applied", @service.apply!(proposal: item, actor: @alice).state
    assert_includes item.reload.body, "Спасибо за сообщение"
    assert item.applied_at
    assert_equal 0, @room.messages.where(user: @alice).count
  end

  test "stale edited source, goal revision and revoked consent block applying" do
    first = @service.create!(room: @room, actor: @alice)
    @incoming.update!(body: "A different issue")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.apply!(proposal: first, actor: @alice)
    end
    second = @service.create!(room: @room, actor: @alice)
    @goal.update!(revision: 2)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.apply!(proposal: second, actor: @alice)
    end
    third = @service.create!(room: @room, actor: @alice)
    AiRoomAutomationConsent.find_by!(room: @room, user: @bob).update!(
      background_context_enabled: false, revision: 2)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @service.apply!(proposal: third, actor: @alice)
    end
    assert_equal 0, @room.messages.where(user: @alice).count
  end

  test "different person cannot apply; dismissed proposal cannot be replayed" do
    item = @service.create!(room: @room, actor: @alice)
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @service.apply!(proposal: item, actor: @bob)
    end
    assert_equal "dismissed", @service.dismiss!(proposal: item, actor: @alice).state
    assert_nil @service.latest!(room: @room, actor: @alice)
    assert_raises(AiWorkspace::OfflineReplyProposal::Unavailable) do
      @service.apply!(proposal: item, actor: @alice)
    end
    @policy.update!(reply_mode: "off", revision: 2)
    assert_raises(AiWorkspace::OfflineReplyProposal::Unavailable) do
      @service.create!(room: @room, actor: @alice)
    end
  end
end
