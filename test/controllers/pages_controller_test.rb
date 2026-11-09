require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "home page is public and has useful account entry actions" do
    get root_path

    assert_response :success
    assert_select "h1", text: /Conversations, without the clutter/
    assert_select "main a[href=?]", new_user_registration_path, text: "Create account"
    assert_select "main a[href=?]", new_user_session_path, text: "Log in"
    assert_select "nav a[href=?]", rooms_path, count: 0
    assert_select "nav", text: /My messages/, count: 0
  end

  test "signed-in home shows only currently accessible room labels and real unread attention" do
    alice, bob = users(:one), users(:two)
    member_room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    member_room.messages.create!(user: bob, body: "Top secret member-body 99")

    stranger = User.create!(email: "home-stranger@example.test",
      password: "test-password-123", display_name: "Stranger")
    forbidden_room = Room.create_private_room([bob, stranger],
      "private_#{[bob.id, stranger.id].sort.join('_')}")
    forbidden_room.messages.create!(user: stranger, body: "Forbidden third-party body 61")

    sign_in alice
    get root_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "h1", text: /Pick up where you left off/
    assert_select ".sd-home-room[href=?]", room_path(member_room), count: 1
    assert_select ".sd-home-room[href=?]", room_path(forbidden_room), count: 0
    assert_select ".sd-home-room__unread", minimum: 1
    assert_select ".sd-home-attention[href=?]", notifications_path, count: 1
    assert_select "main a[href=?]", edit_user_registration_path, count: 1
    assert_not_includes response.body, "Top secret member-body 99"
    assert_not_includes response.body, "Forbidden third-party body 61"
    assert_not_includes response.body, "home-stranger@example.test"
    assert_not_includes response.body, forbidden_room.name
  end

  test "a new member gets a genuine empty home, not fake room counters" do
    newcomer = User.create!(email: "new-home-user@example.test",
      password: "test-password-123")
    sign_in newcomer
    get root_path
    assert_response :success
    assert_select ".sd-home-empty", text: /No conversations yet/
    assert_select ".sd-home-room", count: 0
    assert_select ".sd-home-attention__content strong", text: "0"
    assert_select "main a[href=?]", rooms_path, text: "Browse rooms"
  end

  test "GET home does not change presence or update the signed-in user" do
    user = users(:one)
    sign_in user

    %w[online away offline].each do |presence|
      user.update!(status: presence)
      before = user.reload.attributes.slice("status", "updated_at")

      2.times do
        get root_path
        assert_response :success
        assert_equal before, user.reload.attributes.slice("status", "updated_at"),
          "GET / must be read-only for an authenticated #{presence} user"
      end
    end
  end

  test "signed-in home links directly to conversations and account settings" do
    sign_in users(:one)
    get root_path

    assert_response :success
    assert_select "main a[href=?]", rooms_path, text: "Open inbox"
    assert_select "main a[href=?]", edit_user_registration_path, text: /Profile & settings/
    assert_select "nav a[href=?]", rooms_path, text: "Conversations"
    assert_select "main a[href=?]", new_user_registration_path, count: 0
  end
end
