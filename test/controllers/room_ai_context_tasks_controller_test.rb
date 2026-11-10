require "test_helper"

class RoomAiContextTasksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "Please propose the next steps.")
  end

  test "context tasks are disabled independently in test and cannot publish" do
    sign_in @alice
    count = Message.count
    post generate_room_ai_context_task_path(@room), params: {
      task: { kind: "client_brief", request_id: SecureRandom.uuid, consent: "1" }
    }
    assert_response :service_unavailable
    assert_equal count, Message.count
    assert_equal "no-store", response.headers["Cache-Control"].split(", ").last
  end

  test "unapproved participant history and forged tasks are denied" do
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: @alice).grant!
    sign_in @alice
    AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
      post generate_room_ai_context_task_path(@room), params: {
        task: { kind: "client_proposal", request_id: SecureRandom.uuid, consent: "1" }
      }
      assert_response :unprocessable_entity
      assert_not_includes response.body, "Please propose"

      post generate_room_ai_context_task_path(@room), params: {
        task: { kind: "arbitrary_prompt", request_id: SecureRandom.uuid, consent: "1" }
      }
      assert_response :unprocessable_entity
    end
  end
end
