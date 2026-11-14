require "test_helper"
require "securerandom"

class RedisThrottleIntegrationTest < ActiveSupport::TestCase
  test "two independent Redis connections enforce the same fixed-window limit" do
    skip "Redis integration is exercised in its dedicated CI step" unless ENV["REDIS_INTEGRATION"] == "1"

    first = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: ENV.fetch("REDIS_URL"))
    second = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: ENV.fetch("REDIS_URL"))
    identity = SecureRandom.hex(16)
    time = Time.at(1_700_000_040)

    assert_not RequestThrottle.exceeded?(scope: "redis-integration", identity: identity, limit: 3, period: 60.seconds, at: time, cache: first)
    assert_not RequestThrottle.exceeded?(scope: "redis-integration", identity: identity, limit: 3, period: 60.seconds, at: time, cache: second)
    assert_not RequestThrottle.exceeded?(scope: "redis-integration", identity: identity, limit: 3, period: 60.seconds, at: time, cache: first)
    assert RequestThrottle.exceeded?(scope: "redis-integration", identity: identity, limit: 3, period: 60.seconds, at: time, cache: second)
  ensure
    first&.clear
  end

  test "atomic counters remain consistent across parallel Redis callers" do
    skip "Redis integration is exercised in its dedicated CI step" unless ENV["REDIS_INTEGRATION"] == "1"

    first = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: ENV.fetch("REDIS_URL"))
    second = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: ENV.fetch("REDIS_URL"))
    identity = SecureRandom.hex(16)
    go = Queue.new
    ready = Queue.new
    threads = 8.times.map do |i|
      Thread.new do
        ready << true
        go.pop
        RequestThrottle.exceeded?(
          scope: "redis-parallel", identity: identity, limit: 5, period: 60.seconds,
          at: Time.at(1_700_000_040), cache: i.even? ? first : second
        )
      end
    end
    8.times { ready.pop }
    8.times { go << true }
    results = threads.map(&:value)

    assert_equal 3, results.count(true)
    assert_equal 5, results.count(false)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    first&.clear
  end
end
