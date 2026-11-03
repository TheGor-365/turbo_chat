require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "member may create a message and cannot spoof the author" do
    sign_in users(:one)
    assert_difference "Message.count", 1 do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Server owned identity", user_id: users(:two).id }
      }
    end
    assert_redirected_to room_path(rooms(:one))
    assert_equal users(:one).id, Message.order(:id).last.user_id
  end

  test "message bursts return 429 before persisting excess messages" do
    sign_in users(:one)
    30.times do |i|
      post room_messages_path(rooms(:one)), params: { message: { body: "rate test #{i}" } }
      assert_redirected_to room_path(rooms(:one))
    end

    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: { message: { body: "over limit" } }
    end
    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
  end

  test "third party cannot write to private room even by direct id" do
    room = Room.create!(name: "direct-id-private", is_private: true)
    room.participants.create!(user: users(:two))
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(room), params: { message: { body: "intrusion" } }
    end
    assert_response :forbidden
  end
end
