require "test_helper"

class RoomNotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def private_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "only the current member may mute their own private conversation" do
    alice, bob = users(:one), users(:two)
    room = private_room(alice, bob)
    stranger = User.create!(email: "mute-outsider@example.test", password: "secure-password-123")

    patch room_notification_preference_path(room), params: { muted: "true" }
    assert_redirected_to new_user_session_path

    sign_in stranger
    patch room_notification_preference_path(room), params: { muted: "true" }
    assert_response :forbidden
    assert_equal 0, ConversationNotificationPreference.where(room: room).count

    sign_out stranger
    sign_in alice
    get room_path(room)
    assert_select "#room-notification-preference", text: "Mute alerts"

    patch room_notification_preference_path(room), params: {
      muted: "true", user_id: bob.id
    }
    assert_redirected_to room_path(room)
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert ConversationNotificationPreference.find_by!(user: alice, room: room).muted?
    assert_nil ConversationNotificationPreference.find_by(user: bob, room: room)
    get room_path(room)
    assert_select "#room-notification-preference", text: "Unmute alerts"

    patch room_notification_preference_path(room), params: { muted: "false" }
    assert_redirected_to room_path(room)
    assert_not ConversationNotificationPreference.find_by!(user: alice, room: room).muted?
    assert_equal 1, ConversationNotificationPreference.where(user: alice, room: room).count
  end

  test "public room mute requires join membership and remains independent" do
    alice, bob = users(:one), users(:two)
    room = rooms(:one)
    sign_in bob
    patch room_notification_preference_path(room), params: { muted: "true" }
    assert_response :forbidden

    sign_out bob
    sign_in alice
    patch room_notification_preference_path(room), params: { muted: "true" }
    assert_redirected_to room_path(room)
    assert ConversationNotificationPreference.muted_for?(alice, room)
    assert_not ConversationNotificationPreference.muted_for?(bob, room)
  end

  test "malformed mute values never change a persisted setting" do
    alice, bob = users(:one), users(:two)
    room = private_room(alice, bob)
    sign_in alice

    %w[1 yes on falsehood].each do |bad|
      patch room_notification_preference_path(room), params: { muted: bad }
      assert_response :bad_request
    end
    assert_nil ConversationNotificationPreference.find_by(user: alice, room: room)
  end

  test "Turbo mute action returns small replacement without reloading the conversation" do
    alice, bob = users(:one), users(:two)
    room = private_room(alice, bob)
    sign_in alice

    patch room_notification_preference_path(room), params: { muted: "true" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select 'turbo-stream[action="replace"][target="room-notification-preference"]'
    assert_includes response.body, "Unmute alerts"
    assert_not_includes response.body, bob.email

    patch room_notification_preference_path(room), params: { muted: "false" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "Mute alerts"
    assert_not ConversationNotificationPreference.muted_for?(alice, room)
  end

  test "revoked private conversation member cannot change previous mute preference" do
    alice, bob = users(:one), users(:two)
    room = private_room(alice, bob)
    preference = ConversationNotificationPreference.create!(user: alice, room: room, muted: false)
    room.participants.where(user: alice).delete_all

    sign_in alice
    patch room_notification_preference_path(room), params: { muted: "true" }
    assert_response :forbidden
    assert_not preference.reload.muted?
  end
end
