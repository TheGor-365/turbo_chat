require "test_helper"

class PresencePrivacyControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    nonce = SecureRandom.hex(6)
    @alice = User.create!(email: "presence-privacy-alice-#{nonce}@example.test",
      password: "secure-password-123")
    @bob = User.create!(email: "presence-privacy-bob-#{nonce}@example.test",
      password: "secure-password-123")
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @registry = PresenceRegistry.new
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

  test "privacy toggle requires sign in and only changes the authenticated account" do
    patch account_presence_path, params: { share_presence: "false" }
    assert_redirected_to new_user_session_path

    sign_in @alice
    get edit_user_registration_path
    assert_response :success
    assert_select "#presence-privacy-settings", text: /Show when active/
    patch account_presence_path, params: { share_presence: "false", user_id: @bob.id }
    assert_redirected_to edit_user_registration_path
    assert_not @alice.reload.share_presence?
    assert @bob.reload.share_presence?

    get edit_user_registration_path
    assert_select "#presence-privacy-settings", text: /Appear offline/
    patch account_presence_path, params: { share_presence: "true" }
    assert_redirected_to edit_user_registration_path
    assert @alice.reload.share_presence?
    assert @bob.reload.share_presence?
  end

  test "opt-out removes all previous room sessions and masks online from the peer" do
    @registry.heartbeat(room_id: @room.id, user_id: @alice.id, token: "chrome-one", active: true)
    @registry.heartbeat(room_id: @room.id, user_id: @alice.id, token: "chrome-two", active: false)
    assert_equal "online", @registry.status(room_id: @room.id, user_id: @alice.id)

    sign_in @alice
    patch account_presence_path, params: { share_presence: "false" }
    assert_redirected_to edit_user_registration_path
    assert_equal "offline", @registry.status(room_id: @room.id, user_id: @alice.id)

    sign_out @alice
    sign_in @bob
    get presence_room_path(@room)
    assert_response :success
    assert_equal({ "status" => "offline" }, JSON.parse(response.body))
    assert_not_includes response.body, "share_presence"
    assert_not_includes response.body, @alice.email

    # A late/stale Redis heartbeat can never change the HTTP privacy mask.
    @registry.heartbeat(room_id: @room.id, user_id: @alice.id, token: "late", active: true)
    get presence_room_path(@room)
    assert_equal({ "status" => "offline" }, JSON.parse(response.body))
  end

  test "malformed inputs do not change presence visibility" do
    sign_in @alice
    %w[1 yes online hidden nil].each do |value|
      patch account_presence_path, params: { share_presence: value }
      assert_response :bad_request
    end
    assert @alice.reload.share_presence?
  end
end
