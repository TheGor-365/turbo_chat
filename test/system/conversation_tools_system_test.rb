require "application_system_test_case"

class ConversationToolsSystemTest < ApplicationSystemTestCase
  setup do
    @jack = users(:one)
    @eric = users(:two)
    @room = Room.create_private_room([@jack, @eric],
      "private_#{[@jack.id, @eric.id].sort.join('_')}")
  end

  def sign_in
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: @jack.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, wait: 10
  end

  test "status and search are always visible; secondary tools open only on click and close on Escape" do
    sign_in
    visit room_path(@room)
    fill_in "chat-text", with: "Unsent draft stays where it is"
    assert_selector ".sd-conversation-toolbar .realtime-health", visible: true
    assert_selector ".sd-conversation-toolbar button[aria-label='Search messages']", visible: true
    assert_selector "#conversation-tools-panel[hidden]", visible: :all
    assert_no_selector "#conversation-tools-panel", visible: true

    trigger = find("button[aria-label='Conversation tools']")
    trigger.hover
    sleep 0.4
    assert_no_selector "#conversation-tools-panel", visible: true
    assert_equal "false", trigger["aria-expanded"]

    trigger.click
    assert_selector "#conversation-tools-panel:not([hidden])", visible: true
    assert_equal "true", trigger["aria-expanded"]
    within "#conversation-tools-panel" do
      assert_button "Mute alerts"
      assert_button "Sync messages"
      assert_link "AI workspace"
      assert_link "Review document"
    end
    assert_field "chat-text", with: "Unsent draft stays where it is"
    find("button[aria-label='Conversation tools']").send_keys(:escape)
    assert_selector "#conversation-tools-panel[hidden]", visible: :all
    assert_equal "false", find("button[aria-label='Conversation tools']")["aria-expanded"]
    assert_equal 0, @room.messages.count
  end

  test "mute and unmute from the menu keep the menu row after Turbo Stream replacement" do
    sign_in
    visit room_path(@room)
    click_button "Conversation tools"
    within "#conversation-tools-panel" do
      click_button "Mute alerts"
    end
    within "#conversation-tools-panel" do
      assert_button "Unmute alerts", wait: 10
      assert_selector ".sd-conversation-tools__notification .sd-conversation-tools__row"
      click_button "Unmute alerts"
      assert_button "Mute alerts", wait: 10
    end
    assert_equal false, ConversationNotificationPreference.muted_for?(@jack, @room)
  end

  test "people search is collapsed while chatting and expanded on inbox or deliberate click" do
    sign_in
    visit rooms_path
    assert_selector "#side_panel .sd-people-disclosure[open]"
    assert_field "Find people by display name", visible: true

    visit room_path(@room)
    assert_selector "#side_panel .sd-people-disclosure:not([open])", visible: :all
    assert_no_field "Find people by display name", visible: true
    assert_selector "#direct-rooms", visible: true

    find("#sd-users-title").click
    assert_selector "#side_panel .sd-people-disclosure[open]"
    assert_field "Find people by display name", visible: true
    assert_selector "#messages-container", visible: true
  end

  test "tools menu stays inside a 320px mobile viewport without hiding ordinary messages" do
    sign_in
    page.current_window.resize_to(320, 720)
    visit room_path(@room)
    assert_selector ".sd-conversation-name", visible: true
    click_button "Conversation tools"
    assert_selector "#conversation-tools-panel:not([hidden])"
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const menu = document.querySelector("#conversation-tools-panel").getBoundingClientRect()
        return { left: menu.left, right: menu.right, width: innerWidth,
          scrollWidth: document.documentElement.scrollWidth }
      })()
    JS
    assert_operator geometry.fetch("left"), :>=, -1
    assert_operator geometry.fetch("right"), :<=, geometry.fetch("width") + 1
    assert_operator geometry.fetch("scrollWidth"), :<=, geometry.fetch("width") + 1
    assert_selector "#chat-text", visible: true
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
