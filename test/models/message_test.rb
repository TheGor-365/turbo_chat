require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "rejects text that exceeds maximum length" do
    message = Message.new(room: rooms(:one), user: users(:one), body: "x" * 4001)
    refute message.valid?
    assert message.errors[:body].any?
  end

  test "rejects messages without body or files" do
    message = Message.new(room: rooms(:one), user: users(:one), body: "")
    refute message.valid?
  end

  test "rejects messages from users without room membership" do
    message = Message.new(room: rooms(:two), user: users(:one), body: "not allowed")
    refute message.valid?
    assert message.errors[:base].any?
  end
end
