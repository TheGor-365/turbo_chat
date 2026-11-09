require "test_helper"

class DisplayNameProfileTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-in navigation exposes settings and the profile uses a scrollable document layout" do
    sign_in users(:one)

    get rooms_path
    assert_response :success
    assert_select "body.chat-workspace", count: 1
    assert_select 'a.sd-nav__settings[href=?]', edit_user_registration_path, count: 1
    assert_select '#side_panel a.sd-sidebar-self__avatar-link[href=?]', edit_user_registration_path, count: 1
    assert_select '#side_panel a.sd-sidebar-self__settings[href=?]', edit_user_registration_path, count: 1

    get edit_user_registration_path
    assert_response :success
    assert_select "body.chat-workspace", count: 0
    assert_select 'a.sd-nav__settings[href=?]', edit_user_registration_path, count: 1
    assert_select 'a[href=?]', rooms_path, text: "Back to conversations", count: 1
    assert_select 'input[name="user[current_password]"]', count: 1
    assert_select 'input[type="submit"][value="Save changes"]', count: 1
  end

  test "Signal Deck profile keeps editable Devise fields and presence/delete routes" do
    sign_in users(:one)
    get edit_user_registration_path
    assert_response :success
    assert_select ".sd-account-settings .sd-account-heading h2", text: "Profile & settings"
    assert_select ".sd-account-settings .sd-settings-section", minimum: 4
    assert_select ".sd-account-settings .sd-account-field input[name='user[email]']", count: 1
    assert_select ".sd-account-settings .sd-account-field input[name='user[current_password]']", count: 1
    assert_select ".sd-account-settings label[for='user_avatar']", text: "Choose photo"
    assert_select ".sd-account-settings input[type=file][accept='image/jpeg,image/png,image/webp']", count: 1
    assert_select "#presence-privacy-settings form[action=?]", account_presence_path
    assert_select ".sd-settings-danger form[action=?]", user_registration_path
    assert_select ".sd-account-settings .sd-account-save input[type=submit][value='Save changes']"
    assert_select ".card.border-secondary", count: 0
  end

  test "account changes still require the real current password and show errors" do
    user = users(:one)
    original_email = user.email
    sign_in user

    put user_registration_path, params: { user: {
      email: "unguarded-change@example.test", display_name: "Invalid Save",
      current_password: ""
    } }
    assert_response :unprocessable_entity
    assert_equal original_email, user.reload.email
    assert_nil user.display_name
    assert_select "#error_explanation", minimum: 1
    assert_select "input[name='user[current_password]']", count: 1
  end

  test "Devise sign in signup and reset screens use working first-party forms" do
    get new_user_session_path
    assert_response :success
    assert_select ".sd-auth-page form[action=?] input[name='user[email]']", user_session_path
    assert_select ".sd-auth-page input[name='user[password]'][autocomplete='current-password']"
    assert_select ".sd-auth-page a[href=?]", new_user_registration_path

    get new_user_registration_path
    assert_response :success
    assert_select ".sd-auth-page form[action=?] input[name='user[display_name]']", user_registration_path
    assert_select ".sd-auth-page input[name='user[password_confirmation]']"
    assert_select ".sd-auth-page input[type='file'][name='user[avatar]']"

    get new_user_password_path
    assert_response :success
    assert_select ".sd-auth-page form[action=?] input[name='user[email]']", user_password_path
    assert_select ".sd-auth-page input[type=submit][value='Send me reset password instructions']"
  end

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
    assert_select ".sd-sidebar-self__name", text: "Алиса Demo"
    assert_select "nav .sd-nav__identity", count: 0
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
    assert_select "#single_room .sd-conversation-header .sd-conversation-name", text: "Bob Example"
    assert_select "#messages-container .name", text: "Bob Example"
    assert_no_match(/bob@example\.test/, response.body)
  end
end
