require "test_helper"

class MessageTest < ActiveSupport::TestCase
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

  test "a joinable association alone cannot access private room" do
    room = Room.create!(name: "private-model-test", is_private: true)
    room.joinables.create!(user: users(:one))
    message = room.messages.build(user: users(:one), body: "private")
    assert_not message.valid?
  end
end
