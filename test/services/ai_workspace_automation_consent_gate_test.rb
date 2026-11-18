require "test_helper"

class AiWorkspaceAutomationConsentGateTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @gate = AiWorkspace::AutomationConsentGate.new
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def grant(user, background: true, send: false, outcome: false)
    AiRoomAutomationConsent.create!(room: @room, user: user,
      member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
      background_context_enabled: background, unattended_send_enabled: send,
      scheduled_outcomes_enabled: outcome)
  end

  test "manual history consent alone can NEVER enable background or auto send" do
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "review")
    end
    grant(@alice, send: true, outcome: true)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "unattended")
    end
    grant(@bob)
    result = @gate.check!(room: @room, actor: @alice, mode: "unattended")
    assert result.consent_ready
    assert_equal false, result.execution_authorized
    assert_equal 2, result.members
    assert_equal 0, @room.messages.count
  end

  test "actor needs an additional personal opt-in for unattended send and scheduled outcomes" do
    grant(@alice)
    grant(@bob)
    assert_equal false, @gate.check!(room: @room, actor: @alice,
      mode: "review").execution_authorized
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "unattended")
    end
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "outcome")
    end
    @alice.ai_room_automation_consents.find_by!(room: @room).update!(
      unattended_send_enabled: true, scheduled_outcomes_enabled: true, revision: 2)
    assert_equal false, @gate.check!(room: @room, actor: @alice,
      mode: "outcome").execution_authorized
    assert_equal false, @gate.check!(room: @room, actor: @alice,
      mode: "unattended").execution_authorized
  end

  test "revoke, replace membership or revoke manual context blocks all modes" do
    grant(@alice, send: true, outcome: true)
    grant(@bob)
    @bob.ai_room_automation_consents.find_by!(room: @room).update!(
      background_context_enabled: false, revision: 2)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "review")
    end
    @bob.ai_room_automation_consents.find_by!(room: @room).update!(
      background_context_enabled: true, revision: 3)
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "unattended")
    end
    AiRoomContextConsent.find_by!(room: @room, user: @bob).grant!
    @room.participants.where(user: @bob).delete_all
    @room.participants.create!(user: @bob)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @gate.check!(room: @room, actor: @alice, mode: "review")
    end
  end
end
