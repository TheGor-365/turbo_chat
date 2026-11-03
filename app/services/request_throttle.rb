# Atomic counters work with MemoryStore in tests and RedisCacheStore in production.
# Production must use shared Redis to enforce limits across web workers.
class RequestThrottle
  DEFAULT_PERIOD = 60.seconds

  def self.exceeded?(scope:, identity:, limit:, period: DEFAULT_PERIOD, at: Time.current)
    raise ArgumentError, "invalid limit" unless limit.positive? && period.positive?

    window = (at.to_i / period.to_i)
    digest = Digest::SHA256.hexdigest(identity.to_s)
    key = "throttle:v1:#{scope}:#{window}:#{digest}"
    count = Rails.cache.increment(key, 1, expires_in: period * 2)
    # A missing counter means caching is not operational. Do not silently
    # disable enforcement on production instances.
    raise "Request throttle cache is unavailable" if count.nil?

    count > limit
  end
end
