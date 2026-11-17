require "application_system_test_case"

class QuietDepthRoomGeometrySystemTest < ApplicationSystemTestCase
  test "desktop room fills available pane and composer has a quiet native boundary" do
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(1440, 900)
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    assert_selector "#single_room .sd-conversation-header"
    assert_selector "#single_room #chat-text"

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const bounds = selector => document.querySelector(selector).getBoundingClientRect();
        const main = bounds("#room_container");
        const room = bounds("#single_room");
        const header = bounds(".sd-conversation-header");
        const input = getComputedStyle(document.querySelector("#chat-text"));
        const composer = getComputedStyle(document.querySelector(".sd-message-composer"));
        return {
          roomFillsPane: room.width >= main.width - 72,
          headerStaysInPane: header.left >= main.left && header.right <= main.right + 1,
          noComposerFrame: parseFloat(composer.borderTopWidth) === 0,
          composerFieldBounded: parseFloat(input.borderTopWidth) >= 1,
          noInputGlowAtRest: input.boxShadow === "none",
          noDocumentOverflow: document.documentElement.scrollWidth <= window.innerWidth
        };
      })()
    JS
    metrics.each do |name, result|
      assert_equal true, result, "#{name} failed: #{metrics.inspect}"
    end
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
