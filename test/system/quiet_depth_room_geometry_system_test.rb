require "application_system_test_case"

class QuietDepthRoomGeometrySystemTest < ApplicationSystemTestCase
  test "room fills its pane and the original composer grip resizes an unsent draft" do
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(1440, 900)
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
    visit room_path(room)

    assert_selector "#single_room .sd-conversation-header"
    grip_selector = '.sd-composer-editor-field .sd-quick-beautify-grip[data-resize-editor="manual"]'
    assert_selector grip_selector, visible: true

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const bounds = selector => document.querySelector(selector).getBoundingClientRect()
        const main = bounds("#room_container")
        const room = bounds("#single_room")
        const input = getComputedStyle(document.querySelector("#chat-text"))
        const composer = getComputedStyle(document.querySelector(".sd-message-composer"))
        return {
          roomFillsPane: room.width >= main.width - 72,
          borderlessComposer: parseFloat(composer.borderTopWidth) === 0,
          originalBorderlessInput: parseFloat(input.borderTopWidth) === 0,
          noDocumentOverflow: document.documentElement.scrollWidth <= window.innerWidth
        }
      })()
    JS
    metrics.each { |name, ok| assert_equal true, ok, "#{name} failed: #{metrics.inspect}" }

    before = page.evaluate_script('document.querySelector("#chat-text").getBoundingClientRect().height')
    find(grip_selector).send_keys(:arrow_up)
    after = page.evaluate_script('document.querySelector("#chat-text").getBoundingClientRect().height')
    assert_operator after, :>, before + 10
    fill_in "chat-text", with: "Unsent message — no AI request"
    after_typing = page.evaluate_script('document.querySelector("#chat-text").getBoundingClientRect().height')
    assert_in_delta after, after_typing, 3
    assert_selector ".sd-quick-beautify-panel[hidden]", visible: :all
    assert_equal 0, room.messages.count
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
