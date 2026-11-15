require "application_system_test_case"

class UnifiedToggleSystemTest < ApplicationSystemTestCase
  def login(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def assert_toggle_style(css)
    assert_selector css, visible: true
    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{css.to_json})
        const style = getComputedStyle(input)
        const knob = getComputedStyle(input, "::before")
        return {
          type: input.type,
          width: Math.round(parseFloat(style.width)),
          height: Math.round(parseFloat(style.height)),
          round: parseFloat(style.borderTopLeftRadius) >= 12,
          knob: knob.content !== "none"
        }
      })()
    JS
    assert_equal "checkbox", result.fetch("type")
    assert_equal 43, result.fetch("width")
    assert_equal 25, result.fetch("height")
    assert_equal true, result.fetch("round")
    assert_equal true, result.fetch("knob")
  end

  test "login and room preference checkboxes are visually unified switches" do
    visit new_user_session_path
    assert_toggle_style ".sd-auth-remember input.sd-toggle"
    find("#user_remember_me").check
    assert find("#user_remember_me").checked?
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    room = Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "Keep this unsent."
    click_button "Edit unsent message"
    click_button "Room settings"
    find("#ai-room-settings .sd-room-settings-fold--translation > summary").click
    assert_toggle_style "input[data-incoming-translation-target='toggle']"
    find("#ai-room-settings .sd-room-settings-fold--display > summary").click
    assert_toggle_style "input[data-simple-chat-target='detailToggle']"
    # Paid context tasks are feature-flag gated; a disabled development setup
    # must not render their consent control or allow a provider request.
    assert_no_selector "input[data-ai-draft-target='briefSpendConsent']", visible: :all
    assert_equal 0, room.messages.count
    assert_field "chat-text", with: "Keep this unsent."
  end

  test "multi-source offline review still uses native checkboxes with switch visuals" do
    user, peer = users(:one), users(:two)
    room = Room.create_private_room([user, peer],
      "private_#{[user.id, peer.id].sort.join('_')}")
    message = room.messages.create!(user: peer, body: "A synthetic message for source review")
    login user
    visit room_ai_workspace_path(room)
    assert_toggle_style "#ai-message-#{message.id}.sd-toggle"
    assert_equal false, find("#ai-message-#{message.id}").checked?
    find("#ai-message-#{message.id}").check
    assert find("#ai-message-#{message.id}").checked?
    assert_selector "[data-ai-selection-target=counter]", text: "1 / 8 selected"
    assert_equal 1, room.messages.count
  end
end
