require "test_helper"
require "securerandom"

class RoomAiEvidenceReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @message = @room.messages.create!(user: @bob,
      body: "Подтверждаю: Rails срок проекта 14 дней")
    @path = room_ai_evidence_reviews_path(@room)
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def token
    AiWorkspace::ConversationCoverageSnapshotV2.new.build(
      room: @room, actor: @alice
    ).sources.find { |item| item.message_id == @message.id }.version_sha256
  end

  def submit_review(stance, key: SecureRandom.uuid, version: token)
    post @path, params: {
      review: { message_id: @message.id, source_version: version,
        stance: stance, request_key: key }
    }, as: :json
  end

  test "authenticated human explicitly changes personal position and withdraws" do
    grant_all
    sign_in @alice
    submit_review("acknowledged")
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "personal_stance_not_room_consensus", response.parsed_body.fetch("state")
    assert_equal "acknowledged", response.parsed_body.fetch("personal_stance")
    assert_equal "not_determined", response.parsed_body.fetch("room_approval_state")

    submit_review("disputed")
    assert_response :success
    assert_equal "disputed", response.parsed_body.fetch("personal_stance")
    submit_review("withdrawn")
    assert_response :success
    assert_equal "none", response.parsed_body.fetch("personal_stance")

    assert_equal 3, AiEvidenceReviewEvent.where(room: @room, reviewer: @alice).count
    assert_equal 1, @room.messages.count
  end

  test "source version and consent required; no private text in rejection response" do
    grant_all
    sign_in @alice
    submit_review("acknowledged", version: "0" * 64)
    assert_response :unprocessable_entity
    assert_not_includes response.body, @message.body
    submit_review("acknowledged")
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post @path, params: { review: {
      message_id: @message.id, stance: "disputed", source_version: "0" * 64,
      request_key: SecureRandom.uuid
    } }, as: :json
    assert_response :forbidden
    assert_not_includes response.body, @message.body
    assert_equal 1, AiEvidenceReviewEvent.where(room: @room).count
  end

  test "guest and nonparticipant cannot affect room reviews" do
    grant_all
    post @path, params: { review: {
      message_id: @message.id, stance: "acknowledged",
      source_version: "0" * 64, request_key: SecureRandom.uuid
    } }, as: :json
    assert_response :unauthorized

    outsider = User.create!(email: "fcc22-outsider@example.test",
      password: "secure-password-123")
    sign_in outsider
    post @path, params: { review: {
      message_id: @message.id, stance: "acknowledged",
      source_version: "0" * 64, request_key: SecureRandom.uuid
    } }, as: :json
    assert_response :forbidden
    assert_equal 0, AiEvidenceReviewEvent.count
  end
end
