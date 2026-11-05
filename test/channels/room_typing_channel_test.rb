require "test_helper"

class RoomTypingChannelTest < ActionCable::Channel::TestCase
  tests RoomTypingChannel
  include ActiveSupport::Testing::TimeHelpers

  def private_room
    alice, bob = users(:one), users(:two)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "private participant subscribes to own recipient-specific typing stream" do
    room = private_room
    stub_connection current_user: users(:one)
    subscribe room_id: room.id

    assert subscription.confirmed?
    assert_has_stream RoomTypingChannel.stream_name(room.id, users(:one).id)
  end

  test "nonmember cannot subscribe to a private typing stream" do
    room = private_room
    outsider = User.create!(email: "typing-outsider@example.test", password: "secure-password-123")
    stub_connection current_user: outsider
    subscribe room_id: room.id
    assert subscription.rejected?
  end

  test "public room is not a private typing stream" do
    stub_connection current_user: users(:one)
    subscribe room_id: rooms(:one).id
    assert subscription.rejected?
  end

  test "user identity, message text, and recipient stream cannot be spoofed" do
    room = private_room
    alice, bob = users(:one), users(:two)
    stub_connection current_user: alice
    subscribe room_id: room.id
    stream = RoomTypingChannel.stream_name(room.id, bob.id)

    assert_broadcasts stream, 1 do
      perform :typing, { user_id: bob.id, room_id: rooms(:two).id, body: "SECRET KEYSTROKES" }
    end

    events = broadcasts(stream)
    payload = JSON.parse(events.last)
    assert_equal "typing", payload["type"]
    assert_equal room.id, payload["room_id"]
    assert_equal alice.id, payload["user_id"]
    assert_not payload.key?("body")
  end

  test "revoked participant cannot keep broadcasting on an old subscription" do
    room = private_room
    alice, bob = users(:one), users(:two)
    stub_connection current_user: alice
    subscribe room_id: room.id
    stream = RoomTypingChannel.stream_name(room.id, bob.id)
    room.participants.where(user: alice).delete_all

    assert_broadcasts stream, 0 do
      perform :typing
      perform :stopped
    end
  end

  test "throttling bounds repeated server-side typing signals" do
    room = private_room
    alice, bob = users(:one), users(:two)
    stub_connection current_user: alice
    subscribe room_id: room.id
    stream = RoomTypingChannel.stream_name(room.id, bob.id)

    # Fixed-window limiter: avoid crossing a minute boundary mid-loop.
    travel_to Time.utc(2026, 11, 6, 10, 0, 30) do
      assert_broadcasts stream, RoomTypingChannel::MAX_SIGNALS_PER_MINUTE do
        (RoomTypingChannel::MAX_SIGNALS_PER_MINUTE + 5).times { perform :typing }
      end
    end
  end
end
