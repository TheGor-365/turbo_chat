require "test_helper"
require "minitest/mock"

class RoomAiContextRepliesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "Can you confirm the scope?")
  end

  def params_for
    { reply: { consent: "1", request_id: SecureRandom.uuid, hint: "" } }
  end

  test "contextual inference is independently disabled and cannot post messages" do
    sign_in @alice
    before = Message.count
    post generate_room_ai_context_reply_path(@room), params: params_for
    assert_response :service_unavailable
    assert_equal before, Message.count
    assert_equal "no-store", response.headers["Cache-Control"].split(", ").last
  end

  test "member without eligible incoming source is rejected before processing" do
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: @alice).grant!
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post generate_room_ai_context_reply_path(@room), params: params_for
      assert_response :unprocessable_entity
      assert_not_includes response.body, "Can you confirm"
    end
  end

  test "guest and outsider do not receive history or source message IDs" do
    post generate_room_ai_context_reply_path(@room), params: params_for
    assert_redirected_to new_user_session_path

    outsider = User.create!(email: "h3g-other@example.test", password: "secure-password")
    sign_in outsider
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post generate_room_ai_context_reply_path(@room), params: params_for
      assert_response :forbidden
      assert_not_includes response.body, "Can you confirm"
    end
  end

  test "peer-only grant permits response but revoked source suppresses returned candidate" do
    incoming = @room.messages.first
    grant = AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob)
    grant.grant!
    output = AiWorkspace::ContextReplyGeneration::Result.new(
      text: "Candidate requiring review", model: "fake", 
      source_ids: [incoming.id], omitted: 0, cost_ticks: 0)
    fake = Object.new
    fake.define_singleton_method(:call) { |**_opts| output }
    sign_in @alice
    before = Message.count
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextReplyGeneration.stub(:new, ->(**_opts) { fake }) do
        post generate_room_ai_context_reply_path(@room), params: params_for
        assert_response :success
        assert_equal [incoming.id], JSON.parse(response.body).fetch("source_message_ids")
        grant.revoke!
        post generate_room_ai_context_reply_path(@room), params: params_for
        assert_response :unprocessable_entity
        assert_not_includes response.body, output.text
      end
    end
    assert_equal before, Message.count
  end

end
