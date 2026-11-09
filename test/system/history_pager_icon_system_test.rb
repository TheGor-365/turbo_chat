require "application_system_test_case"

class HistoryPagerIconSystemTest < ApplicationSystemTestCase
  test "history uses a keyboard-addressable icon and loads earlier messages without full navigation" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    now = Time.current
    Message.insert_all!(27.times.map do |index|
      {
        room_id: room.id, user_id: alice.id, body: "History batch #{index}",
        created_at: now - 1.day + index.seconds,
        updated_at: now - 1.day + index.seconds
      }
    end)

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    visit room_path(room)
    assert_selector "#messages-container > [id^='message_']", count: 10
    assert_no_text "History batch 12"
    assert_selector "#pager a.sd-history-more[aria-label='Load earlier messages'][title='Load earlier messages']"
    assert_no_selector "#pager a.btn-primary", visible: :all

    page.current_window.resize_to(390, 844)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")

    pager = find("#pager a.sd-history-more", visible: true)
    assert_operator pager.evaluate_script("this.getBoundingClientRect().width"), :>=, 44
    assert_operator pager.evaluate_script("this.getBoundingClientRect().height"), :>=, 44
    pager.click

    assert_selector "#messages-container > [id^='message_']", minimum: 20, wait: 15
    assert_text "History batch 12"
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_no_selector "#pager a.btn-primary", visible: :all
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
