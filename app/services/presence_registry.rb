# Ephemeral, per-DM presence backed by shared Redis. No persistent
# users.status updates, no room-wide/public/global presence broadcasts.
#
# Each authenticated ActionCable subscription owns a server-generated token.
# Redis sorted sets retain multiple independent browser sessions, with expiry
# timestamps so lost disconnect callbacks cannot leave a permanent green dot.
class PresenceRegistry
  TTL_SECONDS = 45
  HEARTBEAT_SECONDS = 12
  STATUSES = %w[offline away online].freeze

  TOUCH_SCRIPT = <<~LUA.freeze
    local now = tonumber(ARGV[1])
    local expiry = tonumber(ARGV[2])
    local token = ARGV[3]
    local active = ARGV[4] == "1"
    local ttl = tonumber(ARGV[5])
    for i = 1, 2 do
      redis.call("ZREMRANGEBYSCORE", KEYS[i], "-inf", now)
    end
    local previous = 0
    if redis.call("ZCARD", KEYS[1]) > 0 then previous = 1 end
    if redis.call("ZCARD", KEYS[2]) > 0 then previous = 2 end
    redis.call("ZADD", KEYS[1], expiry, token)
    if active then
      redis.call("ZADD", KEYS[2], expiry, token)
    else
      redis.call("ZREM", KEYS[2], token)
    end
    redis.call("EXPIRE", KEYS[1], ttl * 2)
    redis.call("EXPIRE", KEYS[2], ttl * 2)
    local current = 1
    if redis.call("ZCARD", KEYS[2]) > 0 then current = 2 end
    return {previous, current}
  LUA

  REMOVE_SCRIPT = <<~LUA.freeze
    local now = tonumber(ARGV[1])
    local token = ARGV[2]
    for i = 1, 2 do
      redis.call("ZREMRANGEBYSCORE", KEYS[i], "-inf", now)
    end
    local previous = 0
    if redis.call("ZCARD", KEYS[1]) > 0 then previous = 1 end
    if redis.call("ZCARD", KEYS[2]) > 0 then previous = 2 end
    redis.call("ZREM", KEYS[1], token)
    redis.call("ZREM", KEYS[2], token)
    local current = 0
    if redis.call("ZCARD", KEYS[1]) > 0 then current = 1 end
    if redis.call("ZCARD", KEYS[2]) > 0 then current = 2 end
    if current == 0 then redis.call("DEL", KEYS[1], KEYS[2]) end
    return {previous, current}
  LUA

  STATUS_SCRIPT = <<~LUA.freeze
    local now = tonumber(ARGV[1])
    for i = 1, 2 do
      redis.call("ZREMRANGEBYSCORE", KEYS[i], "-inf", now)
    end
    if redis.call("ZCARD", KEYS[2]) > 0 then return 2 end
    if redis.call("ZCARD", KEYS[1]) > 0 then return 1 end
    return 0
  LUA

  def initialize(redis: nil)
    @redis = redis
  end

  def heartbeat(room_id:, user_id:, token:, active:, at: Time.current)
    keys = keys_for(room_id, user_id)
    now = at.to_i
    codes = with_redis { |redis| redis.eval(TOUCH_SCRIPT, keys: keys, argv: [now, now + TTL_SECONDS, token, active ? 1 : 0, TTL_SECONDS]) }
    { previous: STATUSES.fetch(codes[0]), current: STATUSES.fetch(codes[1]) }
  end

  def leave(room_id:, user_id:, token:, at: Time.current)
    codes = with_redis { |redis| redis.eval(REMOVE_SCRIPT, keys: keys_for(room_id, user_id), argv: [at.to_i, token]) }
    { previous: STATUSES.fetch(codes[0]), current: STATUSES.fetch(codes[1]) }
  end

  # Drop every live browser token when the owner opts out of sharing
  # presence. The HTTP snapshot also checks the persisted privacy flag.
  def hide(room_id:, user_id:, at: Time.current)
    previous = status(room_id: room_id, user_id: user_id, at: at)
    with_redis { |redis| redis.del(*keys_for(room_id, user_id)) }
    { previous: previous, current: "offline" }
  end

  def status(room_id:, user_id:, at: Time.current)
    code = with_redis { |redis| redis.eval(STATUS_SCRIPT, keys: keys_for(room_id, user_id), argv: [at.to_i]) }
    STATUSES.fetch(code)
  end

  private

  def keys_for(room_id, user_id)
    prefix = "turbo-chat:#{Rails.env}:presence:v1:room:#{Integer(room_id)}:user:#{Integer(user_id)}"
    ["#{prefix}:sessions", "#{prefix}:visible"]
  end

  def with_redis
    return yield @redis if @redis

    # One short-lived connection per service action; no Redis client is
    # held by a long-lived ActionCable channel across worker restarts.
    client = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/#{Rails.env.test? ? 4 : 1}"))
    yield client
  ensure
    client&.close
  end
end
