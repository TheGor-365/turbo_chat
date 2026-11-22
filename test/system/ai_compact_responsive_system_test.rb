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
      # Composer drafts are restored per browser: normalize its input to
      # empty before testing the auto-grow delta, not an inherited tall draft.
      fill_in "chat-text", with: ""
      page.execute_script(<<~JS)
        const field = document.querySelector('#chat-text')
        delete field.dataset.manualHeight
        field.dispatchEvent(new Event('input', {bubbles:true}))
      JS
      initial = page.evaluate_script("document.querySelector('#chat-text').getBoundingClientRect().height")
      fill_in "chat-text", with: "A longer test draft with several sections. " * 13
      grown = page.evaluate_script("document.querySelector('#chat-text').getBoundingClientRect().height")
      assert_operator grown, :>, initial
      assert_operator grown, :<=, 190

      find(".sd-mobile-composer-toolbar [data-action*='openAi']").click
      find("#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='message']").click
      assert_selector "#ai-draft-panel:not([hidden])"
      expand_ai_style(:draft)
      assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6
      assert_selector "#ai-draft-panel .sd-ai-provider-details:not([open])", visible: :all
      assert_no_selector "#ai-draft-panel .sd-ai-manual-generate .sd-ai-consent-note"
      assert_selector "#ai-draft-panel .sd-ai-policy-card--cost li", text: /Each paid action is explicit/, visible: :all
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

  test "narrow mobile composer keeps full-width center input between AI and Send" do
    page.current_window.resize_to(390, 844)
    sign_in_jack
    visit room_path(room)
    fill_in "chat-text", with: "Human draft remains private"
    assert_selector ".sd-mobile-composer-toolbar", visible: true
    assert_no_selector "#sd-mobile-workspace[open]"
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const rect = selector => document.querySelector(selector).getBoundingClientRect()
        const input = rect(".composer-controls #chat-text")
        const send = rect(".composer-controls .composer-send")
        const ai = rect(".composer-controls .sd-adaptive-ai-action")
        const tools = rect(".sd-mobile-composer-toolbar")
        const status = rect(".sd-mobile-composer-toolbar button")
        // This QA room has no messages. Measure the real loaded bubble CSS
        // with a disposable, non-persisted DOM sample instead of seeding Send.
        const bubble = document.createElement("div")
        bubble.className = "sd-message-bubble"
        document.querySelector("#messages-container").appendChild(bubble)
        const bubbleFont = parseFloat(getComputedStyle(bubble).fontSize)
        bubble.remove()
        return {width:input.width,left:input.left,right:input.right,top:input.top,bottom:input.bottom,
          sendTop:send.top,sendBottom:send.bottom,sendRight:send.right,aiBottom:ai.bottom,
          viewport:innerWidth,documentWidth:document.documentElement.scrollWidth,
          statusWidth:status.width,toolsBottom:tools.bottom,
          bubbleFont:bubbleFont}
      })()
    JS
    assert_operator metrics["width"], :>=, 180
    assert_operator metrics["left"], :>=, 0
    assert_operator metrics["right"], :<=, metrics["viewport"] + 1
    assert_in_delta metrics["bottom"], metrics["sendBottom"], 2
    assert_in_delta metrics["bottom"], metrics["aiBottom"], 8
    assert_operator metrics["toolsBottom"], :<=, metrics["top"]
    assert_operator metrics["sendRight"], :<=, metrics["viewport"] + 1
    assert_operator metrics["documentWidth"], :<=, metrics["viewport"] + 2
    assert_operator metrics["statusWidth"], :>=, 35
    assert_selector ".sd-mobile-composer-toolbar [data-action*='openAttachments'][aria-label='Tools']"
    find(".sd-mobile-composer-toolbar [data-action*='openStatus']").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector "#sd-mobile-workspace .sd-composer-status-pill", count: 6
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='plan']", visible: true
    # B16 user contract changed: 6 real 44px controls PLUS a full six-tile nav.
    assert_operator page.evaluate_script("document.querySelector('#sd-mobile-workspace').getBoundingClientRect().height"), :<=, 610
    # B15: desktop-style pills stay in six distinct, 44px aligned mobile rows.
    # Pending text is green by design, while the actual pending clock stays amber.
    appearance = page.evaluate_script(<<~JS)
      (() => {
        const sheet = document.querySelector('#sd-mobile-workspace')
        const pills = [...sheet.querySelectorAll('.sd-composer-status-pill')]
        const rects = pills.map(p => p.getBoundingClientRect())
        const sample = getComputedStyle(pills[0])
        const motion = getComputedStyle(sheet).transitionProperty
        const backdropMotion = getComputedStyle(sheet, '::backdrop').transitionProperty
        const expectedColor = token => {
          const probe = document.createElement('span')
          probe.style.color = `var(${token})`
          sheet.append(probe)
          const color = getComputedStyle(probe).color
          probe.remove()
          return color
        }
        const labelColor = state => {
          const probe = pills[0].cloneNode(true)
          probe.dataset.state = state
          probe.style.cssText = 'position:absolute;visibility:hidden;pointer-events:none'
          sheet.append(probe)
          const color = getComputedStyle(
            probe.querySelector('.sd-composer-status-pill__value')
          ).color
          probe.remove()
          return color
        }
        return {
          aligned: rects.every(r => Math.abs(r.left - rects[0].left) < 2 &&
            Math.abs(r.width - rects[0].width) < 2),
          minTap: rects.every(r => r.height >= 43.5),
          radius: parseFloat(sample.borderTopLeftRadius),
          animated: motion.includes('opacity') && motion.includes('transform') &&
            motion.includes('display') && motion.includes('overlay') &&
            backdropMotion.includes('opacity'),
          pendingGreen: labelColor('pending') === expectedColor('--sd-success'),
          onGreen: labelColor('on') === expectedColor('--sd-success'),
          offRed: labelColor('off') === expectedColor('--sd-danger')
        }
      })()
    JS
    assert_equal true, appearance.fetch("aligned")
    assert_equal true, appearance.fetch("minTap")
    assert_operator appearance.fetch("radius"), :>=, 20
    assert_equal true, appearance.fetch("animated")
    assert_equal true, appearance.fetch("pendingGreen")
    assert_equal true, appearance.fetch("onGreen")
    assert_equal true, appearance.fetch("offRed")
    find("#sd-mobile-workspace .sd-mobile-workspace__close").click
    find(".sd-mobile-composer-toolbar [data-action*='openAttachments']").click
    assert_selector "#sd-mobile-attachments[open]"
    assert_selector "#sd-mobile-attachments .sd-mobile-workspace__heading strong", text: "Tools"
    assert_selector "#sd-mobile-attachments .sd-mobile-attachment-grid > button", count: 3
    assert_operator page.evaluate_script("document.querySelector('#sd-mobile-attachments').getBoundingClientRect().height"), :<=, 300
    assert_includes page.evaluate_script(
      "getComputedStyle(document.querySelector('#sd-mobile-attachments')).transitionProperty"
    ), "overlay"
    find("#sd-mobile-attachments .sd-mobile-workspace__close").click
    find(".sd-mobile-composer-toolbar button[data-action*='openAi']").click
    assert_selector "#sd-mobile-workspace[open]", wait: 10
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs"
    assert_no_selector "#sd-mobile-workspace .sd-composer-disclosure__body--actions", visible: true
    assert_equal "ai", find("#sd-mobile-workspace", visible: :all)[:"data-mode"]
    find("#sd-mobile-workspace .sd-mobile-workspace__close").click
    assert_no_selector "#sd-mobile-workspace[open]"
    assert_equal 14, metrics["bubbleFont"]
    assert_field "chat-text", with: "Human draft remains private"
    assert_equal 0, room.messages.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "mobile workspace tabs share canonical screens without sending a draft" do
    page.current_window.resize_to(390, 844)
    sign_in_jack
    visit room_path(room)
    fill_in "chat-text", with: "Do not send, G1 workspace QA"
    find(".sd-mobile-composer-toolbar [data-action*='openAi']").click
    assert_selector "#sd-mobile-workspace[open]", wait: 10
    find("#sd-mobile-workspace [data-workspace-tab='context']").click
    assert_selector "#sd-ai-context-studio[open]", wait: 10
    assert_no_selector "#sd-mobile-workspace[open]"
    # All contextual inputs preserve native functionality and accessible labels.
    context_geometry = page.evaluate_script(<<~JS)
      (() => {
        const find = selector => document.querySelector('#sd-ai-context-studio ' + selector)
        const start = find("[data-ai-context-studio-target='from']").getBoundingClientRect()
        const finish = find("[data-ai-context-studio-target='to']").getBoundingClientRect()
        const author = find(".sd-ai-context-studio__filter--author").getBoundingClientRect()
        const tabs = find(".sd-workspace-tabs > button[data-workspace-tab]")
        return {datesInline: Math.abs(start.top - finish.top) <= 2,
          authorBelowDates: author.top >= start.bottom - 2,
          linkDecoration: getComputedStyle(tabs).textDecorationLine}
      })()
    JS
    assert_equal true, context_geometry.fetch("datesInline")
    assert_equal true, context_geometry.fetch("authorBelowDates")
    assert_equal "none", context_geometry.fetch("linkDecoration")
    context_design = page.evaluate_script(<<~JS)
      (() => {
        const dialog = document.querySelector('#sd-ai-context-studio')
        const apply = dialog.querySelector('.sd-ai-context-studio__apply')
        const probe = document.createElement('span')
        probe.style.background = 'var(--sd-surface-3)'
        dialog.append(probe)
        const neutral = getComputedStyle(probe).backgroundColor
        probe.remove()
        const style = getComputedStyle(apply)
        return {muted:style.backgroundColor === neutral,
          outlined:parseFloat(style.borderTopWidth) >= 1,
          rounded:parseFloat(style.borderTopLeftRadius) >= 10,
          sheetExit:getComputedStyle(dialog).transitionProperty.includes('overlay')}
      })()
    JS
    assert_equal true, context_design.fetch("muted")
    assert_equal true, context_design.fetch("outlined")
    assert_equal true, context_design.fetch("rounded")
    assert_equal true, context_design.fetch("sheetExit")
    find("#sd-ai-context-studio [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open]", wait: 10
    assert_no_selector "#sd-ai-context-studio[open]"
    find("#ai-draft-panel [data-workspace-tab='room']").click
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_no_selector "#ai-draft-panel[open]"
    find("#ai-room-settings [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[open][data-view='instructions']", wait: 10
    find("#ai-room-settings [data-workspace-tab='plan']").click
    assert_selector "#sd-ai-effective-plan:not([hidden])", wait: 10
    assert_no_selector "#ai-room-settings[open]"
    assert_field "chat-text", with: "Do not send, G1 workspace QA"
    assert_equal 0, room.messages.count
    assert_equal 0, AiUsageReservation.count
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
      assert_selector "#ai-draft-panel[role='dialog'][aria-modal='false']:not([hidden])"
      assert_equal "dialog", find("#ai-draft-panel").tag_name
      assert_equal true, page.evaluate_script("document.querySelector('#ai-draft-panel').open")
      assert_selector ".sd-ai-sheet-backdrop[hidden]", visible: :all
      assert_equal false, page.evaluate_script("document.querySelector('#ai-draft-panel').matches(':modal')")
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
      expand_ai_style(:draft)
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
  test "three setting explanations stay closed until arrow activation and details animate" do
    page.current_window.resize_to(1440, 900)
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      sign_in_jack
      visit room_path(room)
      click_button "Edit unsent message"
      find("#ai-draft-panel .sd-workspace-tabs [data-workspace-tab='room']").click
      assert_selector "#ai-room-settings .sd-ai-option-disclosure:not([open])", count: 3
      expand_ai_style(:room)
      assert_no_selector "#ai-room-settings .sd-ai-room-option-description", visible: true
      assert_no_selector "#ai-room-settings .sd-ai-smart-consent-note", visible: true
      assert_no_selector "#ai-room-settings #ai-room-auto-explanation", visible: true
      assert_no_selector "#ai-room-settings .sd-ai-member-list", visible: true
      find("#ai-room-settings .sd-ai-members-permission > summary").click
      assert_selector "#ai-room-settings .sd-ai-member-list", visible: true

      find("#ai-room-settings .sd-ai-option-disclosure--spell > summary").click
      assert_selector "#ai-room-settings .sd-ai-option-disclosure--spell[open]"
      assert_selector "#ai-room-settings .sd-ai-room-option-description",
        text: /Built-in browser dictionary/
      motion = page.evaluate_script(<<~JS)
        (() => getComputedStyle(
          document.querySelector("#ai-room-settings .sd-ai-option-disclosure--spell"),
          "::details-content"
        ).transitionDuration)()
      JS
      assert_match(/0\.28s/, motion)
      find("#ai-room-settings .sd-ai-option-disclosure--spell > summary").click
      assert_selector "#ai-room-settings .sd-ai-option-disclosure--spell:not([open])"
      assert_no_selector "#ai-room-settings .sd-ai-room-option-description", visible: true

      find("#ai-room-settings .sd-ai-option-disclosure--smart > summary").click
      assert_selector "#ai-room-settings .sd-ai-smart-consent-note", visible: true
      find("#ai-room-settings .sd-ai-option-disclosure--smart > summary").click

      find("#ai-room-settings .sd-ai-option-disclosure--auto > summary").click
      assert_selector "#ai-room-settings #ai-room-auto-explanation",
        text: /Automatic AI editing is not implemented/
      find("#ai-room-settings .sd-ai-option-disclosure--auto > summary").click
      assert_selector "#ai-room-settings .sd-ai-option-disclosure:not([open])", count: 3
      assert_equal 0, room.messages.count
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "AI sheets show localized titles and centered recipient context with corner close" do
    page.current_window.resize_to(1440, 900)
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in_jack
      visit room_path(room)
      click_button "Edit unsent message"
      assert_selector "#ai-draft-panel .sd-ai-workspace-topbar"
      assert_selector "#ai-draft-panel .sd-unified-sheet__heading", text: "Message settings", visible: true
      assert_operator page.evaluate_script(
        "document.querySelector('#ai-draft-panel .sd-unified-sheet__heading').getBoundingClientRect().width"), :>, 100
      assert_selector "#ai-draft-panel .sd-ai-draft-context", text: /To:/
      assert_selector "#ai-draft-panel .sd-ai-draft-context", text: /Review before Send/
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const dialog = document.querySelector("#ai-draft-panel").getBoundingClientRect()
          const close = document.querySelector("#ai-draft-panel .sd-ai-sheet-close").getBoundingClientRect()
          const context = document.querySelector("#ai-draft-panel .sd-ai-draft-context").getBoundingClientRect()
          return { closeGap: dialog.right - close.right, closeTop: close.top - dialog.top,
            centerGap: Math.abs((context.left + context.right)/2 - (dialog.left + dialog.right)/2) }
        })()
      JS
      assert_operator geometry.fetch("closeGap"), :<, 56
      assert_operator geometry.fetch("closeTop"), :<, 76
      assert_operator geometry.fetch("centerGap"), :<, 12

      find("#ai-draft-panel .sd-workspace-tabs [data-workspace-tab='room']").click
      assert_selector "#ai-room-settings .sd-unified-sheet__heading", text: "Room settings", visible: true
      assert_operator page.evaluate_script(
        "document.querySelector('#ai-room-settings .sd-unified-sheet__heading').getBoundingClientRect().width"), :>, 100
      assert_no_selector "#ai-room-settings .sd-room-settings-snapshot__item", visible: true
      assert_selector "#ai-room-settings .sd-room-settings-snapshot__item", count: 3, visible: :all
      assert_no_selector "#ai-room-settings .sd-room-ai-instructions__summary", visible: true
      find("#ai-room-settings .sd-workspace-tabs [data-workspace-tab='instructions']").click
      assert_selector "#ai-room-settings[data-view='instructions'] .sd-room-ai-instructions__summary", visible: true
      find("#ai-room-settings .sd-workspace-tabs [data-workspace-tab='room']").click
      assert_selector "#ai-room-settings[data-view='room']", visible: true
      assert_no_selector "#ai-room-settings .sd-ai-conversation-goal", visible: :all
      assert_selector "#ai-room-settings .sd-ai-room-context", text: /Room:/
      assert_selector "#ai-room-settings .sd-ai-room-context", text: /Device:/
      assert_selector "#ai-room-settings .sd-ai-sheet-close"
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
      find("#ai-draft-panel .sd-workspace-tabs [data-workspace-tab='room']").click
      expand_ai_style(:room)
      assert_selector "#ai-room-settings section.sd-ai-room-group--style[aria-label='Preferred writing style']"
      assert_selector "#ai-room-settings .sd-ai-room-group--style h4", text: "Writing style"
      assert_no_selector "#ai-room-settings .sd-ai-room-style-summary svg", visible: :all
      assert_selector "#ai-room-settings .sd-ai-room-style-summary", text: "Polish / Clarity"
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

  test "G1 B16 desktop Status navigates to Plan-shaped modeless Context without touching draft" do
    page.current_window.resize_to(1440, 900)
    sign_in_jack
    visit room_path(room)
    fill_in "chat-text", with: "QA — DO NOT SEND"

    # One real composer status strip temporarily moves into the six-tab shell.
    find(".sd-composer-disclosure--status > summary").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector "#sd-mobile-workspace .sd-composer-status-pill", count: 6
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='context']", visible: true

    find("#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='context']").click
    assert_selector "#sd-ai-context-studio[open]", wait: 10
    assert_no_selector "#sd-mobile-workspace[open]"
    dimensions = page.evaluate_script(<<~JS)
      (() => {
        const sheet = document.querySelector('#sd-ai-context-studio')
        const room = document.querySelector('#room_container').getBoundingClientRect()
        const bounds = sheet.getBoundingClientRect()
        return {
          modal: sheet.matches(':modal'),
          left: bounds.left, right: bounds.right,
          roomLeft: room.left, roomRight: room.right,
          height: bounds.height, viewportHeight: window.innerHeight,
          backdrop: getComputedStyle(sheet,'::backdrop').display
        }
      })()
    JS
    assert_equal false, dimensions.fetch("modal")
    assert_equal "none", dimensions.fetch("backdrop")
    # B17 owner wants a taller, uniformly anchored bottom workspace rather
    # than B16's former 42dvh / 420px cap. Keep a meaningful viewport bound.
    assert_operator dimensions.fetch("height"), :>=, dimensions.fetch("viewportHeight") * 0.53
    assert_operator dimensions.fetch("height"), :<=, dimensions.fetch("viewportHeight") * 0.78 + 2
    assert_operator dimensions.fetch("left"), :>=, dimensions.fetch("roomLeft") - 2
    assert_operator dimensions.fetch("right"), :<=, dimensions.fetch("roomRight") + 2

    find("#sd-ai-context-studio .sd-workspace-tabs [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open][aria-modal='false']", wait: 10
    assert_no_selector "#sd-ai-context-studio[open]"
    assert_field "chat-text", with: "QA — DO NOT SEND"
    assert_equal 0, room.messages.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

end
