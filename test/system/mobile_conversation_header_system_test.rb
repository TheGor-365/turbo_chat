require "application_system_test_case"

class MobileConversationHeaderSystemTest < ApplicationSystemTestCase
  test "mobile room peer title does not overlap the drawer opener or status controls" do
    alice, bob = users(:one), users(:two)
    bob.update!(display_name: "A long conversation peer name for mobile layout")
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    original_size = page.driver.browser.manage.window.size

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, wait: 10
    visit room_path(room)

    [[320, 720], [390, 844], [430, 932]].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      assert_selector ".sd-chat-back", visible: true
      assert_selector ".sd-conversation-name", visible: true
      assert_no_selector "nav .sd-nav__identity", visible: :all
      assert_selector "nav .sd-nav__settings[aria-label='Profile & settings']"
      assert_equal true, page.evaluate_script(<<~JS)
        (() => {
          const menu = document.querySelector('.sd-chat-back').getBoundingClientRect();
          const title = document.querySelector('.sd-conversation-name').getBoundingClientRect();
          const tools = document.querySelector('.sd-conversation-toolbar').getBoundingClientRect();
          return menu.width >= 32 && menu.right <= title.left + 1 &&
            title.right <= tools.left + 1 &&
            menu.top < title.bottom && title.top < menu.bottom &&
            document.documentElement.scrollWidth <= window.innerWidth;
        })()
      JS
    end

    find(".sd-chat-back").click
    assert_selector "#chatroom_container.sd-drawer-open", wait: 5
    assert_selector ".sd-sidebar-self__name", text: alice.chat_label
    assert_selector ".sd-sidebar-self__settings", text: "Profile settings"
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
