require "test_helper"

class RequestThrottleTest < ActiveSupport::TestCase
  test "limits requests per identity and per time window" do
    start = Time.utc(2026, 11, 4, 10, 0, 0)
    assert_not RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 2, period: 60.seconds, at: start)
    assert_not RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 2, period: 60.seconds, at: start)
    assert RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 2, period: 60.seconds, at: start)

    assert_not RequestThrottle.exceeded?(scope: "chat", identity: "bob", limit: 2, period: 60.seconds, at: start)
    assert_not RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 2, period: 60.seconds, at: start + 60.seconds)
  end

  test "scope separation keeps account login and chat independent" do
    start = Time.utc(2026, 11, 4, 10, 0, 0)
    assert_not RequestThrottle.exceeded?(scope: "login", identity: "alice", limit: 1, at: start)
    assert RequestThrottle.exceeded?(scope: "login", identity: "alice", limit: 1, at: start)
    assert_not RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 1, at: start)
  end

  test "invalid limits fail before incrementing" do
    assert_raises(ArgumentError) do
      RequestThrottle.exceeded?(scope: "chat", identity: "alice", limit: 0)
    end
  end
end
