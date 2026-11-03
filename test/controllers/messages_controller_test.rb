require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice = users(:one)
    @bob = users(:two)
    @admin = users(:admin)
  end

  test "anonymous sender is redirected and no message is created" do
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: { message: { body: "anonymous" } }
    end
    assert_redirected_to new_user_session_path
  end

  test "nonmember cannot post into another public room" do
    sign_in @alice
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:two)), params: { message: { body: "bypass" } }
    end
    assert_response :not_found
  end

  test "outsider cannot post to a private direct message" do
    dm = Room.create_private_room([@alice, @bob], "private_#{[@alice.id, @bob.id].sort.join('_')}")
    sign_in @admin
    assert_no_difference "Message.count" do
      post room_messages_path(dm), params: { message: { body: "bypass" } }
    end
    assert_response :not_found
  end

  test "a member can send a text message" do
    sign_in @alice
    assert_difference "Message.count", 1 do
      post room_messages_path(rooms(:one)), params: { message: { body: "Safe message" } }
    end
    assert_response :see_other
    assert_equal @alice.id, Message.order(:id).last.user_id
  end

  test "empty messages are rejected" do
    sign_in @alice
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: { message: { body: "  " } }
    end
    assert_response :see_other
  end
end
