require "application_system_test_case"

# G1/B17: one visual/interaction contract for canonical AI task sheets.
# Existing consent, draft, instruction and source services remain unchanged.
class G1B17UnifiedTaskSheetsSystemTest < ApplicationSystemTestCase
  def sign_in_member
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  test "mobile six destinations share Plan-height bottom sheets and keyboard grips" do
    page.current_window.resize_to(400, 793)
    sign_in_member
    visit room_path(room)
    fill_in "chat-text", with: "QA B17 — do not send"

    find(".sd-mobile-composer-toolbar [data-action*='openStatus']").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector "#sd-mobile-workspace .sd-unified-task-grip[aria-controls='sd-mobile-workspace']"
    assert_selector "#sd-mobile-workspace [data-workspace-tab='status'][aria-current='page']"
    assert_selector "#sd-mobile-workspace .sd-composer-status-pill", count: 6

    find("#sd-mobile-workspace [data-workspace-tab='plan']").click
    assert_selector "#sd-ai-effective-plan:not([hidden])", wait: 10
    assert_selector "#sd-ai-effective-plan .sd-ai-effective-plan__grip"
    assert_field "chat-text", with: "QA B17 — do not send"
    composer = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector("#chat-text").getBoundingClientRect()
        const panel = document.querySelector("#sd-ai-effective-plan").getBoundingClientRect()
        return {inputBottom:input.bottom, inputTop:input.top,
          panelBottom:panel.bottom, height:innerHeight}
      })()
    JS
    assert_operator composer.fetch("inputTop"), :>=, 0
    assert_operator composer.fetch("inputBottom"), :<=, composer.fetch("height")
    assert_operator composer.fetch("panelBottom"), :<=, composer.fetch("inputTop") + 4

    find("#sd-ai-effective-plan [data-workspace-tab='context']").click
    assert_selector "#sd-ai-context-studio[open]", wait: 10
    assert_no_selector "#sd-ai-effective-plan:not([hidden])"
    grip = find("#sd-ai-context-studio .sd-unified-task-grip")
    initial = page.evaluate_script(
      "document.querySelector('#sd-ai-context-studio').getBoundingClientRect().height")
    grip.send_keys(:arrow_up)
    enlarged = page.evaluate_script(
      "document.querySelector('#sd-ai-context-studio').getBoundingClientRect().height")
    assert_operator enlarged, :>, initial

    find("#sd-ai-context-studio [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[open][data-view='instructions']", wait: 10
    assert_selector "#ai-room-settings .sd-unified-task-grip"
    assert_selector "#ai-room-settings .sd-room-ai-instructions__summary", visible: true

    find("#ai-room-settings [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open]", wait: 10
    assert_selector "#ai-draft-panel .sd-unified-task-grip"
    find("#ai-draft-panel [data-workspace-tab='room']").click
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_no_selector "#ai-draft-panel[open]"
    assert_field "chat-text", with: "QA B17 — do not send"

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector("#ai-room-settings").getBoundingClientRect()
        const viewport = window.innerHeight
        return {bottom:viewport - panel.bottom, height:panel.height,
          screenWidth:document.documentElement.scrollWidth}
      })()
    JS
    assert_in_delta 0, geometry.fetch("bottom"), 3
    assert_operator geometry.fetch("height"), :>=, 0.70 * 793
    assert_operator geometry.fetch("screenWidth"), :<=, 402
    assert_equal 0, room.messages.count
    assert_equal 0, AiUsageReservation.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "desktop Message and Instructions use matching bottom geometry without sending" do
    page.current_window.resize_to(1440, 900)
    sign_in_member
    visit room_path(room)
    fill_in "chat-text", with: "B17 visual contract — do not send"
    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel[open]"
    first = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector("#ai-draft-panel").getBoundingClientRect()
        return {height:rect.height, bottom:innerHeight - rect.bottom,
          grip:!!document.querySelector("#ai-draft-panel .sd-unified-task-grip")}
      })()
    JS
    find("#ai-draft-panel [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[data-view='instructions'][open]"
    second = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector("#ai-room-settings").getBoundingClientRect()
        return {height:rect.height, bottom:innerHeight - rect.bottom,
          grip:!!document.querySelector("#ai-room-settings .sd-unified-task-grip")}
      })()
    JS
    assert_equal true, first.fetch("grip")
    assert_equal true, second.fetch("grip")
    assert_in_delta first.fetch("height"), second.fetch("height"), 4
    assert_in_delta first.fetch("bottom"), second.fetch("bottom"), 4
    assert_field "chat-text", with: "B17 visual contract — do not send"
    assert_equal 0, room.messages.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
