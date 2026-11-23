require "application_system_test_case"

class QuietDepthMessageSettingsSystemTest < ApplicationSystemTestCase
  test "one compact six-style picker keeps the draft unsent" do
    room = Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "Draft stays unsent."
    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel[open] #ai-draft-title", text: "Message settings"
    # D3.2: three fast choices reuse the SAME preset controller as the
    # six-style disclosure. Opening it hides the shortcuts (no duplicate row).
    assert_selector "#ai-draft-panel .sd-ai-style-shortcuts button", count: 3, visible: true
    assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6, visible: :all
    find("#ai-draft-panel summary.sd-ai-style-summary").click
    assert_selector "#ai-draft-panel .sd-ai-style-details[open]"
    assert_no_selector "#ai-draft-panel .sd-ai-style-shortcuts", visible: true
    assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6, visible: true
    within("#ai-draft-panel .sd-ai-draft-presets") { click_button "Friendly" }
    assert_selector "#ai-draft-panel summary.sd-ai-style-summary", text: "Friendly"
    within("#ai-draft-panel .sd-ai-draft-presets") { click_button "Technical Summary" }
    assert_field "chat-text", with: "Draft stays unsent."
    assert_equal 0, room.messages.reload.count
    positions = page.evaluate_script(<<~JS)
      (() => {
        const finish = document.querySelector("#ai-draft-panel .sd-ai-ui-section--finish")
        const actions = document.querySelector("#ai-draft-panel .sd-ai-ui-section--actions")
        const rect = document.querySelector("#ai-draft-panel").getBoundingClientRect()
        return [Boolean(finish.compareDocumentPosition(actions) & Node.DOCUMENT_POSITION_FOLLOWING),
          rect.left >= 0 && rect.right <= innerWidth + 1,
          document.documentElement.scrollWidth <= innerWidth + 1]
      })()
    JS
    assert_equal [true, true, true], positions
    page.send_keys(:escape)
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: "Draft stays unsent."
  end
end
