require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "reaction belongs to a message and is unique per user and emoji" do
    msg = rooms(:one).messages.create!(user: users(:one), body: "React here")
    first = msg.message_reactions.create!(user: users(:one), emoji: "👍")
    assert first.persisted?
    assert_raises(ActiveRecord::RecordNotUnique) do
      MessageReaction.create!(message: msg, user: users(:one), emoji: "👍")
    end

    invalid = msg.message_reactions.build(user: users(:one), emoji: "<script>")
    assert_not invalid.valid?

    missing_room_member = msg.message_reactions.build(user: users(:two), emoji: "❤️")
    assert_not missing_room_member.valid?
    assert_match(/not accessible/, missing_room_member.errors.full_messages.to_sentence)
  end

  test "reply target must belong to the same room" do
    parent = rooms(:one).messages.create!(user: users(:one), body: "Original")
    good = rooms(:one).messages.build(user: users(:one), body: "In thread", reply_to: parent)
    assert good.valid?, good.errors.full_messages.inspect

    other = rooms(:two).messages.build(user: users(:two), body: "Across rooms", reply_to: parent)
    assert_not other.valid?
    assert_match(/same conversation/, other.errors.full_messages.to_sentence)

    missing = rooms(:one).messages.build(user: users(:one), body: "Missing parent", reply_to_id: 999_999_999)
    assert_not missing.valid?
  end

  test "deleting a parent retains replies and clears their reference" do
    parent = rooms(:one).messages.create!(user: users(:one), body: "Original")
    reply = rooms(:one).messages.create!(user: users(:one), body: "Response", reply_to: parent)
    parent.destroy!
    assert Message.exists?(reply.id)
    assert_nil reply.reload.reply_to_id
  end

  test "rejects messages from users not in the room" do
    room = Room.create!(name: "restricted-model-test")
    message = room.messages.build(user: users(:one), body: "hello")
    assert_not message.valid?
    assert_includes message.errors[:room], "is not accessible"
  end

  test "requires text or attachment" do
    message = rooms(:one).messages.build(user: users(:one), body: "")
    assert_not message.valid?
    assert_includes message.errors[:base], "Message cannot be blank"
  end

  test "enforces message length" do
    message = rooms(:one).messages.build(user: users(:one), body: "a" * 5001)
    assert_not message.valid?
    assert message.errors[:body].any?
  end

  test "valid member can compose normal message" do
    message = rooms(:one).messages.build(user: users(:one), body: "normal message")
    assert message.valid?, message.errors.full_messages.inspect
  end

  test "public message fanout ignores a departed member even when room association was cached" do
    alice, bob = users(:one), users(:two)
    room = Room.create!(name: "cached-membership-fanout")
    room.joinables.create!(user: alice)
    room.joinables.create!(user: bob)

    before_leave = room.messages.create!(user: bob, body: "Recipient still joined")
    assert Notification.exists?(user: alice, message: before_leave)
    room.joined_users.load
    assert room.association(:joined_users).loaded?

    # Simulate membership revocation through a separate request/process:
    # the old Room instance deliberately retains stale recipient objects.
    room.joinables.where(user: alice).delete_all
    assert_not room.accessible_to?(alice)
    assert room.association(:joined_users).loaded?

    after_leave = room.messages.create!(user: bob, body: "Recipient no longer joined")
    assert_nil Notification.find_by(user: alice, message: after_leave),
      "Former members must never be notified from a cached association"
    assert_not room.joined_users.include?(alice)
  end

  test "a joinable association alone cannot access private room" do
    room = Room.create!(name: "private-model-test", is_private: true)
    room.joinables.create!(user: users(:one))
    message = room.messages.build(user: users(:one), body: "private")
    assert_not message.valid?
  end
end
