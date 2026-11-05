require "test_helper"

class ConversationNotificationPreferenceTest < ActiveSupport::TestCase
  def private_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "muting a DM suppresses only new personal events, not messages or unread" do
    alice, bob = users(:one), users(:two)
    room = private_room(alice, bob)

    before_mute = room.messages.create!(user: bob, body: "Before mute")
    older = Notification.find_by!(user: alice, message: before_mute)

    ConversationNotificationPreference.create!(user: alice, room: room, muted: true)
    assert ConversationNotificationPreference.muted_for?(alice, room)
    assert_not ConversationNotificationPreference.muted_for?(bob, room)

    assert_difference "Message.count", 1 do
      assert_no_difference "Notification.where(user: alice).count" do
        @muted_message = room.messages.create!(user: bob, body: "Arrives while muted")
      end
    end

    assert_nil Notification.find_by(user: alice, message: @muted_message)
    assert Notification.exists?(id: older.id), "Muting must preserve earlier events"
    assert_nil ConversationReadState.find_by(user: alice, room: room),
      "Muting must never advance unread cursor"

    ConversationNotificationPreference.find_by!(user: alice, room: room).update!(muted: false)
    after_unmute = room.messages.create!(user: bob, body: "After unmute")
    assert Notification.exists?(user: alice, message: after_unmute)
    assert_nil Notification.find_by(user: bob, message: after_unmute)
    assert_not Notification.exists?(user: alice, message: @muted_message),
      "Unmuting must not backfill muted events"
  end

  test "mute is personal and applies to joined public rooms too" do
    alice, bob = users(:one), users(:two)
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: bob)

    ConversationNotificationPreference.create!(user: alice, room: room, muted: true)
    incoming = room.messages.create!(user: bob, body: "Joined public room")
    assert_nil Notification.find_by(user: alice, message: incoming)

    outgoing = room.messages.create!(user: alice, body: "Public reply")
    assert Notification.exists?(user: bob, message: outgoing)
    assert_nil Notification.find_by(user: alice, message: outgoing)
  end

  test "preference cannot duplicate the same user room pair" do
    alice = users(:one)
    room = rooms(:one)
    ConversationNotificationPreference.create!(user: alice, room: room, muted: true)
    duplicate = ConversationNotificationPreference.new(user: alice, room: room, muted: false)
    assert_not duplicate.valid?
    assert_equal 1, ConversationNotificationPreference.where(user: alice, room: room).count
  end
end
