require "test_helper"

class RoomPresenceChannelTest < ActionCable::Channel::TestCase
  tests RoomPresenceChannel

  def private_room
    Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def presence_registry
    PresenceRegistry.new
  end

  setup do
    # Minitest workers have independent databases but share the same Redis
    # service. Fixture user IDs would collide across parallel workers and
    # let another test clear the presence keys mid-assertion.
    run_id = SecureRandom.hex(6)
    @alice = User.create!(id: SecureRandom.random_number(1_000_000_000) + 4_000_000_000,
      email: "presence-channel-alice-#{run_id}@example.test", password: "secure-password-123")
    @bob = User.create!(id: SecureRandom.random_number(1_000_000_000) + 6_000_000_000,
      email: "presence-channel-bob-#{run_id}@example.test", password: "secure-password-123")
    @room = private_room
  end

  teardown do
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/4"))
    [@alice, @bob].each do |user|
      prefix = "turbo-chat:#{Rails.env}:presence:v1:room:#{@room.id}:user:#{user.id}"
      redis.del("#{prefix}:sessions", "#{prefix}:visible")
    end
  ensure
    redis&.close
  end

  test "authorized DM member subscribes to only their own private stream" do
    alice, bob = @alice, @bob
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

  test "an existing browser subscription cannot recreate presence after account opt-out" do
    stub_connection current_user: @alice
    subscribe room_id: @room.id
    assert subscription.confirmed?
    perform :heartbeat, { active: true }
    assert_equal "online", presence_registry.status(room_id: @room.id, user_id: @alice.id)

    @alice.update!(share_presence: false)
    presence_registry.hide(room_id: @room.id, user_id: @alice.id)
    perform :heartbeat, { active: true }
    assert_equal "offline", presence_registry.status(room_id: @room.id, user_id: @alice.id)
  end

  test "outsider and public room cannot subscribe or mark a peer online" do
    outsider = User.create!(email: "presence-outsider@example.test", password: "secure-password-123")
    stub_connection current_user: outsider
    subscribe room_id: @room.id
    assert subscription.rejected?

    stub_connection current_user: @alice
    subscribe room_id: rooms(:one).id
    assert subscription.rejected?
    assert_equal "offline", presence_registry.status(room_id: @room.id, user_id: outsider.id)
  end

  test "revoked participant cannot keep updating presence" do
    alice = @alice
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
