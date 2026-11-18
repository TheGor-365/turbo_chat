require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "inbound message creates one event only for recipient and repeated fanout is idempotent" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    assert_difference "Notification.count", 1 do
      @incoming = room.messages.create!(user: bob, body: "Private notification message")
    end
    notification = Notification.find_by!(user: alice, message: @incoming)
    assert_equal "message:#{@incoming.id}", notification.event_key
    assert_equal "new_message", notification.kind
    assert_nil notification.read_at
    assert_nil Notification.find_by(user: bob, message: @incoming)

    assert_no_difference "Notification.count" do
      assert_equal notification.id, Notification.record_message!(@incoming, alice).id
      assert_nil Notification.record_message!(@incoming, bob)
    end
  end

  test "event feed uses current membership and does not reveal departed rooms" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Secret event body")
    note = Notification.find_by!(user: alice, message: incoming)
    assert_includes Notification.visible_to(alice), note
    assert_not_includes Notification.visible_to(bob), note

    room.participants.where(user: alice).delete_all
    assert_not_includes Notification.visible_to(alice), note
  end

  test "deleting a message purges its personal notification" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Will be removed")
    note = Notification.find_by!(user: alice, message: incoming)
    incoming.destroy!
    assert_not Notification.exists?(id: note.id)
  end

  test "a recipient cannot create an event about their own message" do
    alice = users(:one)
    msg = rooms(:one).messages.create!(user: alice, body: "Own outgoing")
    assert_nil Notification.record_message!(msg, alice)
    note = Notification.new(user: alice, message: msg, room: msg.room,
      event_key: "message:#{msg.id}", kind: "new_message")
    assert_not note.valid?
  end
end
