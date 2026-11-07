require "test_helper"

class RoomMessagesChannelTest < ActionCable::Channel::TestCase
  tests RoomMessagesChannel

  test "room member can subscribe to own room stream" do
    stub_connection current_user: users(:one)
    room = rooms(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.confirmed?
    assert_has_stream Turbo::StreamsChannel.send(:stream_name_from, [room, users(:one)])
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

  test "former room member cannot replay a valid signed stream" do
    room = rooms(:one)
    signed = Turbo::StreamsChannel.signed_stream_name([room, users(:one)])
    room.joinables.where(user: users(:one)).delete_all

    stub_connection current_user: users(:one)
    subscribe room_id: room.id, signed_stream_name: signed

    assert subscription.rejected?
  end

  test "membership in one public room does not authorize a different room" do
    own_room = rooms(:one)
    foreign_room = rooms(:two)
    stub_connection current_user: users(:one)
    subscribe room_id: foreign_room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([foreign_room, users(:one)])

    assert subscription.rejected?
    assert own_room.accessible_to?(users(:one))
  end

  test "a valid signature for a different room cannot be rebound to this room" do
    own_room = rooms(:one)
    foreign_room = rooms(:two)
    stub_connection current_user: users(:one)
    subscribe room_id: own_room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([foreign_room, users(:one)])

    assert subscription.rejected?
  end

  test "a private room requires actual participant membership" do
    room = Room.create!(name: "private-channel-check", is_private: true)
    room.joinables.create!(user: users(:one))

    stub_connection current_user: users(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.rejected?
  end

  test "a private room participant can subscribe to their own stream" do
    room = Room.create!(name: "private-channel-authorized", is_private: true)
    room.participants.create!(user: users(:one))

    stub_connection current_user: users(:one)
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.confirmed?
    assert_has_stream Turbo::StreamsChannel.send(:stream_name_from, [room, users(:one)])
  end

  test "private group pending invite has no stream and revoked member cannot reconnect" do
    owner, invitee = users(:one), users(:two)
    room = Room.create!(name: "channel-invite-only-test", is_private: true,
      kind: "private_group", owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    invitation = PrivateGroupInvitation.create!(room: room, user: invitee,
      invited_by: owner)

    stub_connection current_user: invitee
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, invitee])
    assert subscription.rejected?, "Pending invitation is not a subscription"

    room.participants.create!(user: invitee, group_role: "member")
    invitation.update!(status: "accepted")
    stub_connection current_user: invitee
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, invitee])
    assert subscription.confirmed?

    room.participants.where(user: invitee).delete_all
    stub_connection current_user: invitee
    subscribe room_id: room.id,
      signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, invitee])
    assert subscription.rejected?, "Removed member cannot replay copied group signature"
  end

  test "invalid signed stream is rejected" do
    stub_connection current_user: users(:one)
    subscribe room_id: rooms(:one).id, signed_stream_name: "forged"
    assert subscription.rejected?
  end
end
