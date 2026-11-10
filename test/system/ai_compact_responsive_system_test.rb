require "application_system_test_case"
require "minitest/mock"

class AiCompactResponsiveSystemTest < ApplicationSystemTestCase
  def sign_in_jack
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

  test "mobile composer and editor grow to fit actual draft length without leaving the viewport" do
    page.current_window.resize_to(390, 844)
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in_jack
      visit room_path(room)
      assert_selector "textarea#chat-text"
      initial = page.evaluate_script("document.querySelector('#chat-text').getBoundingClientRect().height")
      fill_in "chat-text", with: "A longer test draft with several sections. " * 13
      grown = page.evaluate_script("document.querySelector('#chat-text').getBoundingClientRect().height")
      assert_operator grown, :>, initial
      assert_operator grown, :<=, 190

      click_button "Edit unsent message"
      assert_selector "#ai-draft-panel:not([hidden])"
      assert_selector "#ai-draft-panel .sd-ai-style-details:not([open])", visible: :all
      assert_selector "#ai-draft-panel .sd-ai-provider-details:not([open])", visible: :all
      assert_no_selector "#ai-draft-panel .sd-ai-manual-generate .sd-ai-consent-note"
      assert_selector "#ai-draft-panel .sd-ai-provider-details", text: /Clicking a Grok button approves one paid request/, visible: :all
      assert_no_selector "#ai-draft-panel .sd-ai-manual-consent input"

      metrics = page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#ai-draft-panel').getBoundingClientRect()
          const editor = document.querySelector('#ai-draft-edit').getBoundingClientRect()
          return { left: panel.left, right: panel.right, width: panel.width,
            height: panel.height, innerHeight: window.innerHeight,
            editorHeight: editor.height, windowWidth: window.innerWidth }
        })()
      JS
      assert_operator metrics.fetch("left"), :>=, -1
      assert_operator metrics.fetch("right"), :<=, metrics.fetch("windowWidth") + 1
      assert_operator metrics.fetch("height"), :<=, metrics.fetch("innerHeight") - 16
      assert_operator metrics.fetch("editorHeight"), :<=, 236
      assert_equal 0, room.messages.count
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "desktop Enter is deliberate Send while Shift Enter preserves newline with no premature send" do
    page.current_window.resize_to(1440, 900)
    sign_in_jack
    visit room_path(room)
    field = find("#chat-text")
    assert_equal "textarea", field.tag_name
    fill_in "chat-text", with: "First line"
    field.send_keys([:shift, :enter])
    assert_includes field.value, "\n"
    assert_equal 0, room.messages.count
    field.send_keys("Second line")
    assert_includes field.value, "Second line"
    field.send_keys(:enter)
    assert_selector "#messages-container", text: "First line", wait: 15
    assert_equal 1, room.messages.reload.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "wide sheet owns focus and Escape returns to composer without sending" do
    page.current_window.resize_to(1024, 768)
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in_jack
      visit room_path(room)
      fill_in "chat-text", with: "Synthetic unsent text"
      click_button "Edit unsent message"
      assert_selector "#ai-draft-panel[role='dialog'][aria-modal='true']:not([hidden])"
      assert_equal "dialog", find("#ai-draft-panel").tag_name
      assert_equal true, page.evaluate_script("document.querySelector('#ai-draft-panel').open")
      assert_selector ".sd-ai-sheet-backdrop:not([hidden])"
      metrics = page.evaluate_script(<<~JS)
        (() => {
          const sheet = document.querySelector('#ai-draft-panel').getBoundingClientRect()
          const room = document.querySelector('#room_container').getBoundingClientRect()
          return { left: sheet.left, right: sheet.right, roomLeft: room.left,
            roomRight: room.right, height: sheet.height, viewportHeight: innerHeight }
        })()
      JS
      assert_operator metrics["left"], :>=, metrics["roomLeft"]
      assert_operator metrics["right"], :<=, metrics["roomRight"]
      assert_operator metrics["height"], :<, metrics["viewportHeight"] * 0.85
      find("#ai-draft-panel summary.sd-ai-style-summary").click
      assert_selector "#ai-draft-panel .sd-ai-preset-glyph", count: 6
      find("#ai-draft-panel .sd-ai-style-summary").send_keys(:escape)
      assert_selector "#ai-draft-panel[hidden]", visible: :all
      assert_selector ".sd-ai-sheet-backdrop[hidden]", visible: :all
      assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
      assert_equal 0, room.messages.count
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
  test "compact actions, collapsed settings style and neutral composer focus" do
    page.current_window.resize_to(1440, 900)
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in_jack
      visit room_path(room)
      fill_in "chat-text", with: "Rails 422: inspect validation errors."
      focus_state = page.evaluate_script(<<~JS)
        (() => {
          const input = document.querySelector("#chat-text")
          input.focus()
          const css = getComputedStyle(input)
          return { outline: css.outlineStyle, shadow: css.boxShadow }
        })()
      JS
      assert_equal "none", focus_state.fetch("outline")
      assert_not_equal "none", focus_state.fetch("shadow")

      click_button "Edit unsent message"
      metrics = page.evaluate_script(<<~JS)
        (() => {
          const sheet = document.querySelector("#ai-draft-panel").getBoundingClientRect()
          const action = document.querySelector("#ai-draft-panel .sd-ai-manual-generate .sd-ai-generate-button").getBoundingClientRect()
          return { sheetWidth: sheet.width, actionWidth: action.width }
        })()
      JS
      assert_operator metrics.fetch("actionWidth"), :<, metrics.fetch("sheetWidth") / 2
      within "#ai-draft-panel" do
        click_button "Room settings"
      end
      assert_selector "#ai-room-settings .sd-ai-room-style-picker:not([open])"
      assert_selector "#ai-room-settings .sd-ai-room-style-summary", text: "Polish / Clarity"
      assert_no_selector "#ai-room-settings .sd-ai-room-presets button", visible: true
      find("#ai-room-settings summary.sd-ai-room-style-summary").click
      assert_selector "#ai-room-settings .sd-ai-room-presets button", count: 6
      within "#ai-room-settings .sd-ai-room-presets" do
        click_button "Friendly"
      end
      assert_selector "#ai-room-settings .sd-ai-room-style-summary", text: "Friendly"
      assert_equal 0, room.messages.count
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

end
