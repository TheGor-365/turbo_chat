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
    assert_select "nav svg.sd-icon", minimum: 4
  end

  test "logged-out navigation has usable auth routes and no private identity" do
    get root_path
    assert_response :success
    assert_select 'nav.sd-nav[data-controller=""]', count: 1
    assert_select 'nav.sd-nav a[href=?]', new_user_session_path, text: "Log in", count: 1
    assert_select 'nav.sd-nav a[href=?]', new_user_registration_path, text: "Sign up", count: 1
    assert_select 'a[href=?][aria-label="Profile & settings"]', edit_user_registration_path, count: 0
    assert_select 'button[data-theme-target="toggle"]', count: 1
  end
  test "workspace marks inbox and conversation mode for responsive routing" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice
    get rooms_path
    assert_select '#chatroom_container[data-chat-pane="inbox"]', count: 1

    get room_path(room)
    assert_response :success
    assert_select '#chatroom_container[data-chat-pane="conversation"]', count: 1
    assert_select 'a[href=?][aria-label="Open conversations"][data-action="click->workspace-drawer#open"]', rooms_path, count: 1
    assert_select '#side_panel[data-workspace-drawer-target="panel"]', count: 1
    assert_select '.sd-drawer-backdrop[data-workspace-drawer-target="backdrop"]', count: 1
    assert_select '.sd-conversation-toolbar [aria-label="Conversation presence"]', count: 1
    assert_select '.sd-conversation-toolbar button[aria-label="Search messages"]', count: 1
  end

  test "D3 search and filters use labelled native controls inside compact Signal Deck surfaces" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice

    get rooms_path
    assert_response :success
    assert_select '#inbox-filters.sd-segment a[aria-current="page"]', text: /All/, count: 1
    assert_select '#room-discovery[data-controller="room-discovery"]', count: 1
    assert_select 'button[aria-label="Find public rooms"][aria-expanded="false"]', count: 1
    assert_select 'input[name="name_search"][aria-label="Search public rooms"]', count: 1
    assert_select '#room-discovery-panel[hidden]', count: 1

    get room_path(room)
    assert_response :success
    assert_select '.sd-command[data-controller="message-search"]', count: 1
    assert_select 'button[aria-label="Search messages"][aria-expanded="false"]', count: 1
    assert_select '#message-search-panel[hidden]', count: 1
    assert_select 'input[name="q"][aria-label="Search messages"]', count: 1

    get room_path(room, inbox: "unread")
    assert_response :success
    assert_select '#inbox-filters.sd-segment a[aria-current="page"]', text: /Unread/, count: 1
  end

end
