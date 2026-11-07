require "application_system_test_case"

class SidebarHierarchySystemTest < ApplicationSystemTestCase
  test "desktop rail aligns brand, peer names, and one-row inbox tools without duplicate bells" do
    user = users(:one)
    peer = users(:two)
    Room.create_private_room([user, peer],
      "private_#{[user.id, peer.id].sort.join('_')}")
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(1440, 900)

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path
    fill_in "Find people by display name", with: users(:two).chat_label
    click_button "Search people"
    assert_selector "#users .sd-user-item", wait: 10
    assert_selector "#side_panel .sd-sidebar-self__name", text: user.chat_label
    assert_selector "#side_panel .sd-rail-section", count: 5
    assert_selector "#side_panel #inbox-filters", text: "All"
    assert_selector "#side_panel #inbox-filters", text: "Unread"
    assert_selector "#side_panel #notifications-nav", text: "Activity"
    assert_no_selector "nav .sd-nav__identity", visible: :all

    assert_equal true, page.evaluate_script(<<~JS)
      (() => {
        const bounds = selector => document.querySelector(selector).getBoundingClientRect();
        const brand = bounds('.sd-nav .sd-brand');
        const navActions = bounds('.sd-nav .sd-nav__actions');
        const toolLinks = [...document.querySelectorAll(
          '#inbox-filters .sd-segment__item, #notifications-nav .notification-nav-link'
        )].map(node => node.getBoundingClientRect());
        const avatar = bounds('#users .sd-user-item .chat_pfp');
        const peerName = bounds('#users .sd-user-item .username');
        const self = bounds('#side_panel .sd-sidebar-self');
        const users = bounds('#side_panel .sd-rail-section--users');
        const sectionCount = document.querySelectorAll('#side_panel .sd-rail-section').length;
        return brand.left <= 30 && navActions.right >= window.innerWidth - 30 &&
          sectionCount === 5 &&
          toolLinks.length === 3 &&
          toolLinks.every(r => Math.abs(r.top - toolLinks[0].top) < 2) &&
          toolLinks[0].left < toolLinks[1].left &&
          toolLinks[1].left < toolLinks[2].left &&
          avatar.right <= peerName.left + 1 &&
          peerName.left - avatar.right <= 24 &&
          self.bottom <= users.top + 18 &&
          document.documentElement.scrollWidth <= window.innerWidth;
      })()
    JS
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
