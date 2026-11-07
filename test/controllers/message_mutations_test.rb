require "test_helper"

class MessageMutationsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "author can edit own text without changing author or attachments" do
    message = rooms(:one).messages.create!(user: users(:one), body: "Before edit")
    sign_in users(:one)

    patch room_message_path(rooms(:one), message), params: {
      message: { body: "After edit", user_id: users(:two).id, attachments: [] }
    }

    assert_redirected_to room_path(rooms(:one))
    assert_equal "After edit", message.reload.body
    assert_equal users(:one).id, message.user_id
  end

  test "author can delete own message" do
    message = rooms(:one).messages.create!(user: users(:one), body: "To delete")
    sign_in users(:one)

    assert_difference "Message.count", -1 do
      delete room_message_path(rooms(:one), message)
    end
    assert_redirected_to room_path(rooms(:one))
  end

  test "a different room member cannot edit or delete another author's message" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    message = room.messages.create!(user: users(:one), body: "Keep my message")
    sign_in users(:two)

    get edit_room_message_path(room, message)
    assert_response :forbidden
    patch room_message_path(room, message), params: { message: { body: "Forfeit" } }
    assert_response :forbidden
    assert_no_difference "Message.count" do
      delete room_message_path(room, message)
    end
    assert_response :forbidden
    assert_equal "Keep my message", message.reload.body
  end

  test "outsider to the room cannot modify a message even with a known ID" do
    room = rooms(:one)
    message = room.messages.create!(user: users(:one), body: "Private to room")
    sign_in users(:two)

    patch room_message_path(room, message), params: { message: { body: "Tampered" } }
    assert_response :forbidden
    assert_equal "Private to room", message.reload.body
  end

  test "empty edited body without an attachment is rejected" do
    message = rooms(:one).messages.create!(user: users(:one), body: "Not empty")
    sign_in users(:one)

    patch room_message_path(rooms(:one), message), params: { message: { body: "" } }
    assert_redirected_to edit_room_message_path(rooms(:one), message)
    assert_equal "Not empty", message.reload.body
  end

  test "server renders message actions for the author but not another room member" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    own = room.messages.create!(user: users(:one), body: "My edit controls")
    other = room.messages.create!(user: users(:two), body: "Their message")
    sign_in users(:one)

    get room_path(room)
    assert_response :success
    assert_select "#message_#{own.id} a[href=?]", edit_room_message_path(room, own)
    assert_select "#message_#{own.id} form[action=?]", room_message_path(room, own)
    assert_select "#message_#{other.id} a[href=?]", edit_room_message_path(room, other), count: 0
    assert_select "#message_#{other.id} form[action=?]", room_message_path(room, other), count: 0
  end
end
