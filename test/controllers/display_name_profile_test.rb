require "test_helper"

class DisplayNameProfileTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "sign-up accepts a normalized profile label without exposing the login email" do
    assert_difference "User.count", 1 do
      post user_registration_path, params: { user: {
        email: "new-chat-name@example.test", password: "testing-secure-password-123",
        password_confirmation: "testing-secure-password-123",
        display_name: "  Мария   Անահիտ  "
      } }
    end
    assert_response :redirect
    user = User.find_by!(email: "new-chat-name@example.test")
    assert_equal "Мария Անահիտ", user.display_name
    assert_equal "Мария Անահիտ", user.chat_label
  end

  test "Devise profile edit modifies only the signed-in account and chat sidebar label" do
    alice, bob = users(:one), users(:two)
    sign_in alice
    get edit_user_registration_path
    assert_response :success
    assert_select "input[name='user[display_name]']", count: 1

    put user_registration_path, params: { user: {
      email: alice.email, current_password: "test-password-123",
      display_name: "  Алиса  Demo  "
    } }
    assert_response :redirect
    assert_equal "Алиса Demo", alice.reload.display_name
    assert_nil bob.reload.display_name

    get rooms_path
    assert_response :success
    assert_select "#side_panel .username", text: "Алиса Demo"
    assert_no_match(/bob@example\.test/, response.body)
  end

  test "invalid public label is rejected and not persisted" do
    alice = users(:one)
    sign_in alice
    put user_registration_path, params: { user: {
      email: alice.email, current_password: "test-password-123",
      display_name: "bad@example.test"
    } }
    assert_response :unprocessable_entity
    assert_nil alice.reload.display_name
    assert_select ".field_with_errors", minimum: 1
  end

  test "DM heading and messages use member display name rather than peer email" do
    alice, bob = users(:one), users(:two)
    bob.update!(display_name: "Bob Example")
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Hello from my profile")
    sign_in alice
    get room_path(room)
    assert_response :success
    assert_select "#single_room > h4", text: "Bob Example"
    assert_select "#messages-container .name", text: "Bob Example"
    assert_no_match(/bob@example\.test/, response.body)
  end
end
