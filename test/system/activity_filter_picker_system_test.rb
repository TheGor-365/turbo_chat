require "application_system_test_case"

class ActivityFilterPickerSystemTest < ApplicationSystemTestCase
  def sign_in_user(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  test "room and time selectors match, keyboard remains accessible and time change refreshes results" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    recent = room.messages.create!(user: bob, body: "Recent H22-filter-check")
    old = room.messages.create!(user: bob, body: "Old H22-filter-check")
    old.update_columns(created_at: 4.months.ago, updated_at: 4.months.ago)

    sign_in_user(alice)
    visit notifications_path
    assert_selector "#archive-room", visible: :all
    assert_selector "#archive-period", visible: :all
    assert_selector ".sd-archive-control--room .sd-archive-picker__trigger[role='combobox']:not([hidden])"
    assert_selector ".sd-archive-control--period .sd-archive-picker__trigger[role='combobox']:not([hidden])"
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('.sd-archive-control--room .sd-archive-picker__trigger')).borderTopWidth")
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('.sd-archive-control--period .sd-archive-picker__trigger')).borderTopWidth")

    fill_in "Search messages or filenames", with: "H22-filter-check"
    click_button "Search archive"
    assert_selector "#archive-results [data-archive-message-id='#{recent.id}']", wait: 15
    assert_selector "#archive-results [data-archive-message-id='#{old.id}']"

    trigger = find(".sd-archive-control--period .sd-archive-picker__trigger")
    trigger.click
    assert_selector "#archive-period-options:not([hidden])"
    trigger.send_keys(:arrow_down)
    assert_equal "archive-period-option-week", trigger["aria-activedescendant"]
    trigger.send_keys(:escape)
    assert_selector "#archive-period-options[hidden]", visible: :all
    assert_equal "all", find("#archive-period", visible: :all).value
    assert_equal true, page.evaluate_script(
      "document.activeElement === document.querySelector('.sd-archive-control--period .sd-archive-picker__trigger')")

    trigger.send_keys("p")
    assert_selector "#archive-period-options:not([hidden])"
    assert_equal "archive-period-option-week", trigger["aria-activedescendant"]
    trigger.send_keys(:escape)

    trigger.send_keys(:arrow_down)
    trigger.send_keys(:arrow_down)
    trigger.send_keys(:enter)
    assert_selector ".sd-archive-control--period .sd-archive-picker__trigger", text: "Past month"
    assert_selector "#archive-results [data-archive-message-id='#{recent.id}']", wait: 15
    assert_no_selector "#archive-results [data-archive-message-id='#{old.id}']"
    assert_includes page.current_url, "period=month"
    assert_includes page.current_url, "H22-filter-check"
    assert_equal "month", find("#archive-period", visible: :all).value
    assert_selector "#archive-period-options .sd-archive-picker__option[data-value='month'][aria-selected='true']", visible: :all

    find(".sd-archive-control--period .sd-archive-picker__trigger").click
    find("#archive-period-options .sd-archive-picker__option[data-value='quarter']").click
    assert_selector ".sd-archive-control--period .sd-archive-picker__trigger", text: "Past 3 months"
    assert_selector "#archive-results [data-archive-message-id='#{recent.id}']", wait: 15
    assert_no_selector "#archive-results [data-archive-message-id='#{old.id}']"
    assert_includes page.current_url, "period=quarter"
  end

  test "conversation selection auto-refreshes authorized messages and preserves query and time filters" do
    alice, bob = users(:one), users(:two)
    first_room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    first_message = first_room.messages.create!(user: bob, body: "H22-scoped report in direct chat")
    second_room = Room.create!(name: "H22-public-scope")
    second_room.joinables.create!(user: alice)
    second_message = second_room.messages.create!(user: alice, body: "H22-scoped report in public room")
    outsider = User.create!(email: "activity-filter-other@example.test", password: "test-password-123")
    forbidden_room = Room.create_private_room([bob, outsider],
      "private_#{[bob.id, outsider.id].sort.join('_')}")
    forbidden = forbidden_room.messages.create!(user: bob, body: "H22-scoped private secret")

    sign_in_user(alice)
    visit notifications_path(q: "H22-scoped", kind: "text", period: "all")
    assert_selector "#archive-results [data-archive-message-id='#{first_message.id}']", wait: 15
    assert_selector "#archive-results [data-archive-message-id='#{second_message.id}']"
    assert_no_selector "#archive-results [data-archive-message-id='#{forbidden.id}']"

    find(".sd-archive-control--room .sd-archive-picker__trigger").click
    assert_selector "#archive-room-options:not([hidden])"
    find("#archive-room-options .sd-archive-picker__option[data-value='#{first_room.id}']").click
    assert_selector "#archive-results [data-archive-message-id='#{first_message.id}']", wait: 15
    assert_no_selector "#archive-results [data-archive-message-id='#{second_message.id}']"
    assert_no_selector "#archive-results [data-archive-message-id='#{forbidden.id}']"
    assert_equal first_room.id.to_s, find("#archive-room", visible: :all).value
    assert_includes page.current_url, "room_id=#{first_room.id}"
    assert_includes page.current_url, "kind=text"
    assert_includes page.current_url, "q=H22-scoped"

    find(".sd-archive-control--period .sd-archive-picker__trigger").click
    find("#archive-period-options .sd-archive-picker__option[data-value='month']").click
    assert_selector "#archive-results [data-archive-message-id='#{first_message.id}']", wait: 15
    assert_no_selector "#archive-results [data-archive-message-id='#{second_message.id}']"
    assert_includes page.current_url, "period=month"
    assert_includes page.current_url, "room_id=#{first_room.id}"

    find(".sd-archive-control--room .sd-archive-picker__trigger").click
    find("#archive-room-options .sd-archive-picker__option[data-value='']").click
    assert_selector "#archive-results [data-archive-message-id='#{second_message.id}']", wait: 15
    assert_selector "#archive-results [data-archive-message-id='#{first_message.id}']"
    assert_no_selector "#archive-results [data-archive-message-id='#{forbidden.id}']"
    assert_includes page.current_url, "period=month"
    assert_equal "", find("#archive-room", visible: :all).value
  end

  test "both selectors fit mobile without borders and work in light and dark themes" do
    page.current_window.resize_to(390, 844)
    sign_in_user(users(:one))
    visit notifications_path

    [".sd-archive-control--room", ".sd-archive-control--period"].each do |control|
      find("#{control} .sd-archive-picker__trigger").click
      assert_selector "#{control} .sd-archive-picker__list:not([hidden])"
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const list = document.querySelector("#{control} .sd-archive-picker__list")
          const rect = list.getBoundingClientRect()
          return { left: rect.left, right: rect.right, width: window.innerWidth,
            border: getComputedStyle(list).borderTopWidth }
        })()
      JS
      assert_operator geometry["left"], :>=, 0
      assert_operator geometry["right"], :<=, geometry["width"] + 1
      assert_equal "0px", geometry["border"]
      find("#{control} .sd-archive-picker__trigger").send_keys(:escape)
    end

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="light"]', visible: :all
    assert_selector ".sd-archive-control--room .sd-archive-picker__trigger[aria-expanded='false']"
    find(".sd-archive-control--room .sd-archive-picker__trigger").click
    assert_selector "#archive-room-options:not([hidden])"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
