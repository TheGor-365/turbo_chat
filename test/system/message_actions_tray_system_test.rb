require "application_system_test_case"

class MessageActionsTraySystemTest < ApplicationSystemTestCase
  test "incoming controls are not in the bubble, start hidden and support Escape and outside click" do
    room = Room.create_private_room([users(:one), users(:two)], "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    message = room.messages.create!(user: users(:two), body: "Quiet incoming")
    login_as_browser(users(:one))
    visit room_path(room)
    selector = "#message_#{message.id}"

    assert_selector "#{selector} .sd-message-bubble", text: "Quiet incoming"
    assert_selector "#{selector} .sd-message-actions[hidden]", visible: :all
    assert_no_selector "#{selector} .sd-message-bubble .sd-message-actions", visible: :all
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const message = document.querySelector("#{selector}");
        const bubble = message.querySelector(".sd-message-bubble").getBoundingClientRect();
        const arrow = message.querySelector(".sd-message-action-trigger").getBoundingClientRect();
        return bubble.width >= 190 && arrow.top >= bubble.bottom - 2 &&
          !message.querySelector(".sd-message-bubble").contains(message.querySelector(".sd-message-action-trigger"));
      })()
    JS
    assert_no_selector "#{selector} a[aria-label='Edit']", visible: :all
    assert_no_selector "#{selector} button[aria-label='Delete']", visible: :all

    within selector do
      click_button "Message actions"
      assert_selector ".sd-message-actions:not([hidden])"
      assert_selector "summary[aria-label='React']"
    end
    assert_equal "true", find("#{selector} button[aria-label='Message actions']")["aria-expanded"]
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const message = document.querySelector("#{selector}");
        const dock = message.querySelector(".sd-message-actions");
        const controls = [...dock.children].map(node => node.getBoundingClientRect());
        return controls.length === 2 && controls.every(box => Math.abs(box.top - controls[0].top) < 2)
          && !message.querySelector(".sd-message-bubble").contains(dock);
      })()
    JS

    page.send_keys(:escape)
    assert_selector "#{selector} .sd-message-actions[hidden]", visible: :all
    assert_equal "false", find("#{selector} button[aria-label='Message actions']")["aria-expanded"]
    assert_equal "Message actions", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

    within(selector) { click_button "Message actions" }
    find("#chat-text").click
    assert_selector "#{selector} .sd-message-actions[hidden]", visible: :all
  end

  test "owner gets Reply React Edit Delete in one accessible 320px row; Reply preserves draft focus" do
    room = rooms(:one)
    message = room.messages.create!(user: users(:one), body: "Quiet outgoing")
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(320, 720)
    login_as_browser(users(:one))
    visit room_path(room)
    selector = "#message_#{message.id}"

    within selector do
      click_button "Message actions"
      assert_selector ".sd-message-actions:not([hidden])"
      assert_link "Edit"
      assert_button "Delete"
      assert_selector "summary[aria-label='React']"
    end
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const bubble = document.querySelector("#{selector} .sd-message-bubble").getBoundingClientRect();
        const arrow = document.querySelector("#{selector} .sd-message-action-trigger").getBoundingClientRect();
        return bubble.width >= 170 && arrow.top >= bubble.bottom - 2;
      })()
    JS
    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const dock = document.querySelector("#{selector} .sd-message-actions");
        const controls = [...dock.children].map(node => node.getBoundingClientRect());
        const trigger = document.querySelector("#{selector} .sd-message-action-trigger").getBoundingClientRect();
        return controls.length === 4 &&
          controls.every(box => Math.abs(box.top - controls[0].top) < 2) &&
          trigger.width >= 44 && trigger.height >= 44 &&
          dock.getBoundingClientRect().right <= window.innerWidth &&
          document.documentElement.scrollWidth <= window.innerWidth;
      })()
    JS
    within(selector) { click_button "Reply" }
    assert_selector "#{selector} .sd-message-actions[hidden]", visible: :all
    assert_equal message.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_equal "chat-text", page.evaluate_script("document.activeElement.id")
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
  private

  def login_as_browser(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 5
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end
end
