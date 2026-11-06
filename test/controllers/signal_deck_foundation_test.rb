require "test_helper"

class SignalDeckFoundationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-in workspace uses an accessible icon-first navigation and theme controller" do
    sign_in users(:one)

    get rooms_path
    assert_response :success
    assert_select 'html[data-controller="theme"][data-theme="dark"]', count: 1
    assert_select "body.sd-app.chat-workspace", count: 1
    assert_select 'nav.sd-nav[aria-label="Main navigation"][data-controller="profile-labels"]', count: 1
    assert_select 'a[href=?][aria-label="Profile & settings"]', edit_user_registration_path, count: 1
    assert_select 'a[href=?][aria-label="Conversations"]', rooms_path, count: 1
    assert_select 'button[data-action="theme#cycle"][data-theme-target="toggle"]', count: 1
    assert_select 'button[aria-label="Log out"]', count: 1
    assert_select "nav svg[aria-hidden='true'][viewBox='0 0 24 24']", minimum: 4
  end

  test "logged-out navigation has usable auth routes and no private identity" do
    get root_path
    assert_response :success
    assert_select 'nav.sd-nav[data-controller=""]', count: 1
    assert_select 'a[href=?]', new_user_session_path, text: "Log in", count: 1
    assert_select 'a[href=?]', new_user_registration_path, text: "Sign up", count: 1
    assert_select 'a[href=?][aria-label="Profile & settings"]', count: 0
    assert_select 'button[data-theme-target="toggle"]', count: 1
  end
end
