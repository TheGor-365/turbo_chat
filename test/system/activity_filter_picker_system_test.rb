require "application_system_test_case"

class ActivityFilterPickerSystemTest < ApplicationSystemTestCase
  def sign_in_user(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  test "time filter supports keyboard, escape, typeahead and preserves GET search semantics" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Milestone H22-filters visible only to members")
    sign_in_user(alice)
    visit notifications_path
    assert_selector "select#archive-period", visible: :all
    assert_selector "#archive-period-options[hidden]", visible: :all
    assert_selector ".sd-archive-picker__trigger:not([hidden])[role='combobox'][aria-expanded='false']"

    trigger = find(".sd-archive-picker__trigger")
    trigger.click
    assert_selector "#archive-period-options:not([hidden])"
    assert_equal "all", find("#archive-period", visible: :all).value
    trigger.send_keys(:arrow_down)
    assert_equal "archive-period-option-week", trigger["aria-activedescendant"]
    trigger.send_keys(:escape)
    assert_selector "#archive-period-options[hidden]", visible: :all
    assert_equal "all", find("#archive-period", visible: :all).value
    assert_equal "false", trigger["aria-expanded"]
    assert_equal true, page.evaluate_script(
      "document.activeElement === document.querySelector('.sd-archive-picker__trigger')")

    trigger.send_keys("p")
    assert_selector "#archive-period-options:not([hidden])"
    assert_equal "archive-period-option-week", trigger["aria-activedescendant"]
    trigger.send_keys(:escape)
    assert_equal "all", find("#archive-period", visible: :all).value

    trigger.send_keys(:arrow_down)
    trigger.send_keys(:arrow_down)
    trigger.send_keys(:enter)
    assert_selector "#archive-period-options[hidden]", visible: :all
    assert_equal "month", find("#archive-period", visible: :all).value
    assert_selector ".sd-archive-picker__trigger", text: "Past month"
    assert_selector ".sd-archive-picker__option[aria-selected='true'][data-value='month']"

    fill_in "Search messages or filenames", with: "H22-filters"
    click_button "Search archive"
    assert_includes page.current_url, "period=month"
    assert_selector "#archive-results", text: "Milestone H22-filters visible only to members"

    trigger = find(".sd-archive-picker__trigger")
    trigger.click
    find(".sd-archive-picker__option[data-value='quarter']").click
    assert_equal "quarter", find("#archive-period", visible: :all).value
    assert_selector ".sd-archive-picker__trigger", text: "Past 3 months"
    trigger.click
    find("#archive-title").click
    assert_selector "#archive-period-options[hidden]", visible: :all
    assert_equal "quarter", find("#archive-period", visible: :all).value
  end

  test "time filter is responsive and visible in both themes" do
    page.current_window.resize_to(390, 844)
    sign_in_user(users(:one))
    visit notifications_path
    trigger = find(".sd-archive-picker__trigger")
    trigger.click
    assert_selector "#archive-period-options:not([hidden])"

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const list = document.querySelector("#archive-period-options").getBoundingClientRect()
        return { left: list.left, right: list.right, width: window.innerWidth }
      })()
    JS
    assert_operator geometry["left"], :>=, 0
    assert_operator geometry["right"], :<=, geometry["width"] + 1
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('.sd-archive-picker__list')).borderTopWidth")

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="light"]', visible: :all
    assert_selector ".sd-archive-picker__trigger[aria-expanded='false']"
    find(".sd-archive-picker__trigger").click
    assert_selector "#archive-period-options:not([hidden])"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
