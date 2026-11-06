require "test_helper"

class ProfileLabelsChannelTest < ActionCable::Channel::TestCase
  tests ProfileLabelsChannel

  test "subscription uses only the authenticated account, never the requested user ID" do
    alice, bob = users(:one), users(:two)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    stub_connection current_user: alice
    subscribe user_id: bob.id
    assert subscription.confirmed?
    assert_has_stream ProfileLabelsChannel.stream_name(alice.id)
    assert_equal [alice.id, bob.id].sort,
      ProfileLabelsChannel.visible_profiles(alice).map { |profile| profile[:user_id] }.sort
  end

  test "guest subscriptions are rejected" do
    stub_connection current_user: nil
    subscribe user_id: users(:one).id
    assert subscription.rejected?
  end

  test "changed label reaches self and DM peer but never a stranger" do
    alice, bob = users(:one), users(:two)
    outsider = User.create!(email: "label-outsider@example.test", password: "secure-password-123")
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    assert_broadcasts(ProfileLabelsChannel.stream_name(outsider.id), 0) do
      assert_broadcasts(ProfileLabelsChannel.stream_name(alice.id), 1) do
        assert_broadcasts(ProfileLabelsChannel.stream_name(bob.id), 1) do
          bob.update!(display_name: "  Eric Test ")
        end
      end
    end
    payload = JSON.parse(broadcasts(ProfileLabelsChannel.stream_name(alice.id)).last)
    assert_equal({ "type" => "profile_changed", "user_id" => bob.id, "label" => "Eric Test" }, payload)
    refute_includes payload.to_s, "example.test"
    refute_includes payload.to_s, "message"
    assert_equal [{ user_id: outsider.id, label: outsider.chat_label }],
      ProfileLabelsChannel.visible_profiles(outsider)
  end

  test "invalid or unrelated profile edits do not publish labels" do
    bob = users(:two)
    stream = ProfileLabelsChannel.stream_name(bob.id)
    assert_broadcasts(stream, 0) do
      refute bob.update(display_name: "bad@example.test")
      bob.update!(status: :away)
    end
  end
end
