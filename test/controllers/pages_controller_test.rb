require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "home page is public and has useful account entry actions" do
    get root_path

    assert_response :success
    assert_select "h1", text: /Messages, rooms, and realtime conversations/
    assert_select "main a[href=?]", new_user_registration_path, text: "Create account"
    assert_select "main a[href=?]", new_user_session_path, text: "Log in"
    assert_select "nav a[href=?]", rooms_path, count: 0
    assert_select "nav", text: /My messages/, count: 0
  end

  test "signed-in home links directly to conversations and account settings" do
    sign_in users(:one)
    get root_path

    assert_response :success
    assert_select "main a[href=?]", rooms_path, text: "Open conversations"
    assert_select "main a[href=?]", edit_user_registration_path, text: "Account settings"
    assert_select "nav a[href=?]", rooms_path, text: "Conversations"
    assert_select "main a[href=?]", new_user_registration_path, count: 0
  end
end
