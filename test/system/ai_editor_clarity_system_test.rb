require "application_system_test_case"

class AiEditorClaritySystemTest < ApplicationSystemTestCase
  def login_for_editor(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  test "work styles are visible as six icon cards, with a clear hierarchy and unchanged writing switches" do
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_for_editor(users(:one))
      visit room_path(room)
      fill_in "chat-text", with: "A synthetic message with no AI request"
      click_button "Edit unsent message"

      assert_selector "#ai-draft-panel .sd-ai-ui-section--styles .sd-ai-ui-heading h4",
        text: "Choose a writing style"
      assert_selector "#ai-draft-panel .sd-ai-style-details[open]"
      assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6, visible: true
      assert_selector "#ai-draft-panel .sd-ai-draft-presets .sd-ai-preset-glyph", count: 6
      assert_selector "#ai-draft-panel .sd-ai-draft-presets .sd-ai-preset-caption", count: 6
      assert_selector "#ai-draft-panel .sd-ai-ui-section--actions", text: "AI actions"
      assert_selector "#ai-draft-panel .sd-ai-ui-action-grid .sd-ai-custom-instructions"
      assert_selector "#ai-draft-panel .sd-ai-ui-action-grid .sd-ai-source-review"
      assert_selector "#ai-draft-panel .sd-ai-ui-section--finish", text: "Finish editing"

      within "#ai-draft-panel .sd-ai-draft-presets" do
        click_button "Friendly"
      end
      assert_selector "#ai-draft-panel button[data-preset-id='friendly'][aria-pressed='true']"
      assert_selector "#ai-draft-panel summary.sd-ai-style-summary", text: "Friendly"
      assert_no_selector "#ai-draft-panel summary.sd-ai-style-summary", text: "Warm and natural"

      click_button "Room settings"
      assert_selector "#ai-room-settings .sd-ai-room-style-picker[open]"
      assert_selector "#ai-room-settings .sd-ai-room-presets button", count: 6, visible: true
      assert_selector "#ai-room-settings .sd-ai-room-presets .sd-ai-preset-glyph", count: 6
      assert_selector "#ai-room-settings .sd-ai-room-group--options", text: "Writing assistance"
      assert_selector "#ai-room-settings .sd-ai-room-option--spell [role='switch']", count: 1
      assert_selector "#ai-room-settings .sd-ai-room-option--smart [role='switch']", count: 1
      assert_selector "#ai-room-settings .sd-ai-room-option--auto [role='switch']", count: 1
      assert_selector "#ai-room-settings .sd-ai-option-disclosure:not([open])", count: 3
      assert_field "chat-text", with: "A synthetic message with no AI request"
      assert_equal 0, room.messages.reload.count
    end
  end

  test "320px viewport keeps visible cards contained, editable and dismissible" do
    original = page.current_window.size
    page.current_window.resize_to(320, 720)
    login_for_editor(users(:one))
    visit room_path(room)
    fill_in "chat-text", with: "Unsent preview"
    click_button "Edit unsent message"

    assert_selector "#ai-draft-panel .sd-ai-style-details[open]"
    assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6, visible: true
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector("#ai-draft-panel")
        const buttons = [...panel.querySelectorAll(".sd-ai-draft-presets button")]
        const box = panel.getBoundingClientRect()
        return box.left >= -1 && box.right <= innerWidth + 1 &&
          box.height <= innerHeight - 12 &&
          buttons.every(el => {
            const r = el.getBoundingClientRect()
            return r.left >= box.left - 1 && r.right <= box.right + 1
          }) &&
          document.documentElement.scrollWidth <= innerWidth + 1
      })()
    JS
    click_button "Close draft review"
    assert_field "chat-text", with: "Unsent preview"
    assert_equal 0, room.messages.count
  ensure
    page.current_window.resize_to(original.width, original.height) if original
  end
end
