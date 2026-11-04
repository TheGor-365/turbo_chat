require "test_helper"
require "securerandom"
require "timeout"
require "json"

# Verifies Redis transport across two real OS processes.
# This does not replace browser WebSocket authorization or reconnect tests.
class RedisCableProcessTest < ActiveSupport::TestCase
  test "ActionCable broadcasts reach a separate Redis subscriber process" do
    skip "dedicated Redis ActionCable CI step" unless ENV["REDIS_CABLE_INTEGRATION"] == "1"

    stream = "turbo-chat:cross-process:#{SecureRandom.hex(12)}"
    nonce = SecureRandom.hex(12)
    ready_read, ready_write = IO.pipe
    data_read, data_write = IO.pipe

    child = Process.fork do
      ready_read.close
      data_read.close
      client = Redis.new(url: ENV.fetch("REDIS_URL"))

      client.subscribe(stream) do |subscription|
        subscription.subscribe do
          ready_write.write("1")
          ready_write.close
        end

        subscription.message do |_channel, payload|
          data_write.write(payload)
          data_write.close
          client.unsubscribe(stream)
        end
      end
      exit! 0
    rescue StandardError
      exit! 1
    end

    ready_write.close
    data_write.close
    Timeout.timeout(10) { assert_equal "1", ready_read.read(1) }

    # Uses the actual ActionCable Redis adapter instead of the test adapter.
    ActionCable.server.broadcast(stream, { "nonce" => nonce, "type" => "cross-process" })

    payload = Timeout.timeout(10) { JSON.parse(data_read.read) }
    assert_equal nonce, payload.fetch("nonce")
    assert_equal "cross-process", payload.fetch("type")

    status = Timeout.timeout(10) { Process.waitpid2(child).last }
    assert status.success?, "Redis subscriber worker exited unsuccessfully"
    child = nil
  ensure
    [ready_read, ready_write, data_read, data_write].compact.each do |pipe|
      pipe.close unless pipe.closed?
    end
    if child
      begin
        Process.kill("TERM", child)
        Process.waitpid(child)
      rescue Errno::ESRCH, Errno::ECHILD
        # Child was already reaped.
      end
    end
  end
end
