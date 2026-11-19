require "test_helper"

class DefaultTurboStreamChannelTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "a replayed signed stream name is rejected by generic channel" do
    stub_connection current_user: users(:one)
    room = rooms(:one)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([room, users(:one)])

    assert subscription.rejected?
  end
end
