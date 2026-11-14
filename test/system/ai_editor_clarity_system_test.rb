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
    page.current_window.resize_to(*original) if original
  end
  test "room settings show compact icon categories and a three-column style grid" do
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_for_editor(users(:one))
      visit room_path(room)
      fill_in "chat-text", with: "Keep this draft"
    click_button "Edit unsent message"
    click_button "Room settings"

    assert_selector "#ai-room-settings .sd-room-settings-content"
    # The redundant introductory box is intentionally gone. Keep one
    # accessible heading and an icon-led six-card selector instead.
    assert_no_selector "#ai-room-settings .sd-room-settings-intro"
    assert_selector "#ai-room-settings .sd-ai-room-group--style .sd-ai-ui-heading__icon .sd-icon"
    assert_no_selector "#ai-room-settings .sd-ai-room-group--style .sd-ai-ui-heading p"
    assert_selector "#ai-room-settings .sd-ai-room-style-picker[open]"
    assert_selector "#ai-room-settings .sd-ai-room-presets button", count: 6, visible: true
    assert_selector "#ai-room-settings .sd-ai-room-group--options", text: "Writing assistance"
    assert_selector "#ai-room-settings .sd-ai-room-option--spell [role='switch']", count: 1
    assert_selector "#ai-room-settings .sd-ai-room-option--smart [role='switch']", count: 1
    assert_selector "#ai-room-settings .sd-ai-room-option--auto [role='switch']", count: 1

    assert_selector "#ai-room-settings .sd-room-settings-fold--translation:not([open])"
    assert_selector "#ai-room-settings .sd-room-settings-fold--display:not([open])"
    assert_selector "#ai-room-settings .sd-room-settings-fold__icon .sd-icon", count: 2
    # Verify actual card layout rather than parsing grid-template-columns,
    # which may serialize differently across browser engines and widths.
    layout = page.evaluate_script(<<~JS)
      (() => {
        const content = document.querySelector("#ai-room-settings .sd-room-settings-content")
        const main = document.querySelector("#ai-room-settings")
        const cards = Array.from(document.querySelectorAll("#ai-room-settings .sd-ai-room-presets > button"))
        const rects = cards.map(card => card.getBoundingClientRect())
        const tolerance = 2
        const expectedColumns = window.innerWidth <= 400 ? 2 : 3
        const sameRow = rects.slice(0, expectedColumns).every(rect =>
          Math.abs(rect.top - rects[0].top) <= tolerance)
        const nextRow = rects[expectedColumns].top > rects[0].top + tolerance
        return {
          fitsContent: content.getBoundingClientRect().width <= 872,
          fitsDialog: content.getBoundingClientRect().right <= main.getBoundingClientRect().right + tolerance,
          sameRow,
          nextRow,
          expectedColumns
        }
      })()
    JS
    assert_equal true, layout.fetch("fitsContent"), layout.inspect
    assert_equal true, layout.fetch("fitsDialog"), layout.inspect
    assert_equal true, layout.fetch("sameRow"), layout.inspect
    assert_equal true, layout.fetch("nextRow"), layout.inspect

    find("#ai-room-settings .sd-room-settings-fold--translation > summary").click
    assert_selector "#ai-room-settings .sd-room-settings-fold--translation[open]"
    assert_selector "select[data-incoming-translation-target='locale']", visible: true
    # The localized state is synchronized by Stimulus after the settings DOM
    # becomes visible. Wait for initialization, not just for the static select.
    assert_selector "#ai-room-settings [data-incoming-translation-target='summaryState'][data-enabled]", wait: 10
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const room = document.querySelector("#single_room")
        const state = document.querySelector("[data-incoming-translation-target='summaryState']")
        const copy = JSON.parse(room.dataset.incomingTranslationCopyValue)
        return state.textContent.trim() === (state.dataset.enabled === "true" ? copy.on : copy.off)
      })()
    JS
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const state = document.querySelector("[data-incoming-translation-target='summaryState']")
        const toggle = document.querySelector("[data-incoming-translation-target='toggle']")
        return state.dataset.enabled === String(toggle.checked)
      })()
    JS

    find("#ai-room-settings .sd-room-settings-fold--display > summary").click
    assert_selector "input[data-simple-chat-target='detailToggle']", visible: true
    click_button "Close writing settings"
    assert_field "chat-text", with: "Keep this draft"
    assert_equal 0, room.messages.count
    end
  end

  test "320px room settings keep categories and cards inside the viewport" do
    original = page.current_window.size
    page.current_window.resize_to(320, 720)
    login_for_editor(users(:one))
    visit room_path(room)
    click_button "Edit unsent message"
    click_button "Room settings"

    assert_selector "#ai-room-settings .sd-room-settings-content"
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const dialog = document.querySelector("#ai-room-settings").getBoundingClientRect()
        const content = document.querySelector("#ai-room-settings .sd-room-settings-content").getBoundingClientRect()
        const presets = [...document.querySelectorAll("#ai-room-settings .sd-ai-room-presets button")]
        const columns = getComputedStyle(document.querySelector("#ai-room-settings .sd-ai-room-presets")).gridTemplateColumns
        return dialog.left >= -1 && dialog.right <= innerWidth + 1 &&
          content.left >= dialog.left - 1 && content.right <= dialog.right + 1 &&
          columns.split(" ").length === 2 &&
          presets.every(el => {
            const r = el.getBoundingClientRect()
            return r.left >= content.left - 1 && r.right <= content.right + 1
          })
      })()
    JS
    click_button "Close writing settings"
  ensure
    page.current_window.resize_to(*original) if original
  end

  test "AI panels scroll without a sticky dark strip and lower settings disclose smoothly" do
    login_for_editor(users(:one))
    visit room_path(room)
    fill_in "chat-text", with: "Keep this message unsent"
    click_button "Edit unsent message"

    assert_equal "static", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-draft-panel .sd-ai-workspace-topbar')).position"
    )
    click_button "Room settings"
    assert_selector "#ai-room-settings:not([hidden])"
    assert_equal "static", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-room-settings .sd-ai-workspace-topbar')).position"
    )

    # Fixed columns avoid sideways repositioning of the other card on expansion.
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const group = document.querySelector("#ai-room-settings .sd-room-settings-more")
        const fold = group.querySelector(".sd-room-settings-fold--translation")
        const style = getComputedStyle(fold, "::details-content")
        return getComputedStyle(group).gridTemplateColumns.split(" ").length === 2 &&
          getComputedStyle(fold).gridColumnEnd === "auto" &&
          style.transitionProperty.includes("block-size")
      })()
    JS

    find("#ai-room-settings .sd-room-settings-fold--translation > summary").click
    assert_selector "#ai-room-settings .sd-room-settings-fold--translation[open]"
    assert_selector "select[data-incoming-translation-target='locale']", visible: true
    find("#ai-room-settings .sd-room-settings-fold--translation > summary").click
    assert_selector "#ai-room-settings .sd-room-settings-fold--translation:not([open])"

    find("#ai-room-settings .sd-room-settings-fold--display > summary").click
    assert_selector "input[data-simple-chat-target='detailToggle']", visible: true
    find("#ai-room-settings .sd-room-settings-fold--display > summary").click
    assert_selector "#ai-room-settings .sd-room-settings-fold--display:not([open])"

    assert_field "chat-text", with: "Keep this message unsent"
    assert_equal 0, room.messages.count
  end

end
