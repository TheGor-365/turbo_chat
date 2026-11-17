require "test_helper"
require "securerandom"

class AiWorkspaceEvidenceReviewRecorderV1Test < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
    @message = @room.messages.create!(user: @bob,
      body: "Предлагаю разработку на Rails за 14 дней")
    @service = AiWorkspace::EvidenceReviewRecorderV1.new
  end

  def version
    AiWorkspace::ConversationCoverageSnapshotV2.new.build(
      room: @room, actor: @alice
    ).sources.find { |source| source.message_id == @message.id }.version_sha256
  end

  def record(stance:, key: SecureRandom.uuid, token: version, actor: @alice)
    @service.call(room: @room, actor: actor, message_id: @message.id.to_s,
      source_version: token, stance: stance, request_key: key)
  end

  test "one author can acknowledge, dispute and explicitly withdraw without group agreement" do
    accepted = record(stance: "acknowledged")
    disputed = record(stance: "disputed")
    withdrawal_key = SecureRandom.uuid
    withdrawn = record(stance: "withdrawn", key: withdrawal_key)
    retried_withdrawal = record(stance: "withdrawn", key: withdrawal_key)
    assert_equal "replayed", retried_withdrawal.fetch(:operation)
    assert_equal withdrawn.fetch(:event_id), retried_withdrawal.fetch(:event_id)
    assert_equal %w[acknowledged disputed withdrawn],
      AiEvidenceReviewEvent.where(room: @room, reviewer: @alice)
        .order(:id).pluck(:stance)
    assert_equal "personal_stance_not_room_consensus", accepted.fetch(:state)
    assert_equal "not_determined", accepted.fetch(:room_approval_state)
    assert_equal "disputed", disputed.fetch(:personal_stance)
    assert_equal "none", withdrawn.fetch(:personal_stance)
    assert_equal @message.id, withdrawn.fetch(:message_id)
    assert_equal 1, @room.messages.count
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      record(stance: "withdrawn")
    end
  end

  test "same key is replay-safe and reusing it for another action fails closed" do
    token = version
    key = SecureRandom.uuid
    first = record(stance: "acknowledged", key: key, token: token)
    second = record(stance: "acknowledged", key: key, token: token)
    assert_equal "recorded", first[:operation]
    assert_equal "replayed", second[:operation]
    assert_equal first[:event_id], second[:event_id]
    assert_equal 1, AiEvidenceReviewEvent.where(room: @room).count
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      record(stance: "disputed", key: key, token: token)
    end
    unchanged = record(stance: "acknowledged", token: token)
    assert_equal "unchanged", unchanged[:operation]
    assert_equal 1, AiEvidenceReviewEvent.where(room: @room).count
  end

  test "source edit invalidates original human stance and old version tokens" do
    old = version
    record(stance: "acknowledged", token: old)
    @message.update!(body: "Новый срок: 30 дней")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      record(stance: "disputed", token: old)
    end
    result = record(stance: "disputed", token: version)
    assert_equal "disputed", result[:personal_stance]
    assert_equal 2, AiEvidenceReviewEvent.where(room: @room).count
  end

  test "revoked consent or departing source author blocks writes" do
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      record(stance: "acknowledged", token: "0" * 64)
    end
    AiRoomContextConsent.find_by!(room: @room, user: @bob).grant!
    @room.participants.where(user: @bob).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized,
      AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection) do
      record(stance: "acknowledged", token: "0" * 64)
    end
    assert_equal 0, AiEvidenceReviewEvent.count
  end

  test "invalid key, token, stance or message reference never persists" do
    token = version
    cases = [
      { stance: "approved", token: token },
      { stance: "acknowledged", token: "0" * 63 },
      { stance: "acknowledged", token: "0" * 64 },
      { stance: "acknowledged", key: "not-a-uuid", token: token }
    ]
    cases.each do |options|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        record(**options)
      end
    end
    assert_equal 0, AiEvidenceReviewEvent.count
  end

  test "another participant cannot adopt the first participant's explicit event" do
    first = record(stance: "acknowledged")
    another = record(stance: "disputed", actor: @bob)
    assert_equal "not_determined", another.fetch(:room_approval_state)
    assert_not_equal first[:event_id], another[:event_id]
    assert_equal 2, AiEvidenceReviewEvent.where(room: @room).count
  end
end
