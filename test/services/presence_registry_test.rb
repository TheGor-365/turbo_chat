require "test_helper"

class PresenceRegistryTest < ActiveSupport::TestCase
  setup do
    @room_id = SecureRandom.random_number(1_000_000_000) + 2_000_000_000
    @alice_id = SecureRandom.random_number(1_000_000_000) + 2_000_000_000
    @bob_id = @alice_id + 1
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/4"))
    @registry = PresenceRegistry.new(redis: @redis)
  end

  teardown do
    [@alice_id, @bob_id].each do |user_id|
      prefix = "turbo-chat:#{Rails.env}:presence:v1:room:#{@room_id}:user:#{user_id}"
      @redis.del("#{prefix}:sessions", "#{prefix}:visible")
    end
    @redis.close
  end

  test "two browser sessions do not mark their user offline when only one closes" do
    now = Time.current
    assert_equal "offline", @registry.status(room_id: @room_id, user_id: @alice_id, at: now)
    first = @registry.heartbeat(room_id: @room_id, user_id: @alice_id, token: "first", active: true, at: now)
    assert_equal({ previous: "offline", current: "online" }, first)
    second = @registry.heartbeat(room_id: @room_id, user_id: @alice_id, token: "second", active: false, at: now)
    assert_equal({ previous: "online", current: "online" }, second)

    first_left = @registry.leave(room_id: @room_id, user_id: @alice_id, token: "first", at: now)
    assert_equal({ previous: "online", current: "away" }, first_left)
    assert_equal "away", @registry.status(room_id: @room_id, user_id: @alice_id, at: now)

    @registry.heartbeat(room_id: @room_id, user_id: @alice_id, token: "second", active: true, at: now)
    assert_equal "online", @registry.status(room_id: @room_id, user_id: @alice_id, at: now)
    @registry.leave(room_id: @room_id, user_id: @alice_id, token: "second", at: now)
    assert_equal "offline", @registry.status(room_id: @room_id, user_id: @alice_id, at: now)
  end

  test "stale sessions expire even if WebSocket disconnect callback was lost" do
    now = Time.current
    @registry.heartbeat(room_id: @room_id, user_id: @alice_id, token: "dead-browser", active: true, at: now)
    assert_equal "online", @registry.status(room_id: @room_id, user_id: @alice_id, at: now + 44.seconds)
    assert_equal "offline", @registry.status(room_id: @room_id, user_id: @alice_id, at: now + 46.seconds)
  end

  test "presence is scoped to one room and one user, never global" do
    now = Time.current
    @registry.heartbeat(room_id: @room_id, user_id: @alice_id, token: "one", active: true, at: now)
    assert_equal "online", @registry.status(room_id: @room_id, user_id: @alice_id, at: now)
    assert_equal "offline", @registry.status(room_id: @room_id, user_id: @bob_id, at: now)
    assert_equal "offline", @registry.status(room_id: @room_id + 1, user_id: @alice_id, at: now)
  end
end
