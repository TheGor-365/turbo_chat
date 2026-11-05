require "test_helper"

class RoomPresenceControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob], "private_#{[@alice.id, @bob.id].sort.join('_')}")
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

  test "only private conversation participants can read peer status" do
    get presence_room_path(@room)
    assert_redirected_to new_user_session_path

    outsider = User.create!(email: "presence-controller-outsider@example.test", password: "secure-password-123")
    sign_in outsider
    get presence_room_path(@room)
    assert_response :forbidden

    sign_out outsider
    sign_in @alice
    get presence_room_path(rooms(:one))
    assert_response :forbidden

    get presence_room_path(@room)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal({ "status" => "offline" }, JSON.parse(response.body))
    assert_not_includes response.body, @bob.email
  end

  test "snapshot returns only current DM peer status and never a forged user id" do
    @registry.heartbeat(room_id: @room.id, user_id: @bob.id, token: "session", active: true)
    sign_in @alice
    get presence_room_path(@room), params: { user_id: @alice.id }
    assert_response :success
    assert_equal({ "status" => "online" }, JSON.parse(response.body))
    assert_not_includes response.body, @bob.email

    sign_out @alice
    sign_in @bob
    get presence_room_path(@room), params: { user_id: @bob.id }
    assert_equal({ "status" => "offline" }, JSON.parse(response.body))
  end
end
