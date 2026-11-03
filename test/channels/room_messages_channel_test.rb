require "test_helper"

class RoomMessagesChannelTest < ActionCable::Channel::TestCase
  tests RoomMessagesChannel

  test "room member can subscribe to own room stream" do
    stub_connection current_user: users(:one)
    room = rooms(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.confirmed?
    assert_has_stream Turbo::StreamsChannel.stream_name_from([room, users(:one)])
  end

  test "member cannot subscribe to a different account's stream" do
    stub_connection current_user: users(:one)
    room = rooms(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:two)])

    assert subscription.rejected?
  end

  test "nonmember cannot subscribe even with a copied valid signature" do
    stub_connection current_user: users(:two)
    room = rooms(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.rejected?
  end

  test "invalid signed stream is rejected" do
    stub_connection current_user: users(:one)
    subscribe room_id: rooms(:one).id, signed_stream_name: "forged"
    assert subscription.rejected?
  end
end
