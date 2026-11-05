require "test_helper"

class RoomInboxChannelTest < ActionCable::Channel::TestCase
  tests RoomInboxChannel

  test "subscribes only to authenticated account's own inbox stream" do
    alice, bob = users(:one), users(:two)
    stub_connection current_user: alice
    subscribe user_id: bob.id, room_id: rooms(:two).id

    assert subscription.confirmed?
    assert_has_stream RoomInboxChannel.stream_name(alice.id)
  end

  test "anonymous inbox subscriptions are rejected" do
    stub_connection current_user: nil
    subscribe user_id: users(:one).id
    assert subscription.rejected?
  end

  test "notifications contain no message bodies or peer identity" do
    alice, bob = users(:one), users(:two)
    stream = RoomInboxChannel.stream_name(alice.id)
    other = RoomInboxChannel.stream_name(bob.id)

    assert_broadcasts(stream, 1) do
      assert_broadcasts(other, 0) do
        RoomInboxChannel.notify(alice)
      end
    end

    event = JSON.parse(broadcasts(stream).last)
    assert_equal({ "type" => "changed" }, event)
  end
end
