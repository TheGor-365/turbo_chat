require "test_helper"

class RoomPresenceChannelTest < ActionCable::Channel::TestCase
  tests RoomPresenceChannel

  def private_room
    alice, bob = users(:one), users(:two)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  def presence_registry
    PresenceRegistry.new
  end

  setup do
    @room = private_room
  end

  teardown do
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/4"))
    [users(:one), users(:two)].each do |user|
      prefix = "turbo-chat:#{Rails.env}:presence:v1:room:#{@room.id}:user:#{user.id}"
      redis.del("#{prefix}:sessions", "#{prefix}:visible")
    end
  ensure
    redis&.close
  end

  test "authorized DM member subscribes to only their own private stream" do
    alice, bob = users(:one), users(:two)
    stub_connection current_user: alice
    subscribe room_id: @room.id, user_id: bob.id
    assert subscription.confirmed?
    assert_has_stream RoomPresenceChannel.stream_name(@room.id, alice.id)

    stream = RoomPresenceChannel.stream_name(@room.id, bob.id)
    assert_broadcasts(stream, 1) do
      perform :heartbeat, { active: true, user_id: bob.id, text: "NOT SENT" }
    end
    assert_equal "online", presence_registry.status(room_id: @room.id, user_id: alice.id)
    assert_equal "offline", presence_registry.status(room_id: @room.id, user_id: bob.id)
    payload = JSON.parse(broadcasts(stream).last)
    assert_equal({ "type" => "presence_changed" }, payload)
  end

  test "outsider and public room cannot subscribe or mark a peer online" do
    outsider = User.create!(email: "presence-outsider@example.test", password: "secure-password-123")
    stub_connection current_user: outsider
    subscribe room_id: @room.id
    assert subscription.rejected?

    stub_connection current_user: users(:one)
    subscribe room_id: rooms(:one).id
    assert subscription.rejected?
    assert_equal "offline", presence_registry.status(room_id: @room.id, user_id: outsider.id)
  end

  test "revoked participant cannot keep updating presence" do
    alice = users(:one)
    stub_connection current_user: alice
    subscribe room_id: @room.id
    assert subscription.confirmed?
    perform :heartbeat, { active: true }
    assert_equal "online", presence_registry.status(room_id: @room.id, user_id: alice.id)

    @room.participants.where(user: alice).delete_all
    perform :heartbeat, { active: false }
    assert_equal "online", presence_registry.status(room_id: @room.id, user_id: alice.id),
      "Revoked stream cannot mutate state; TTL will clean up stale session"
  end
end
