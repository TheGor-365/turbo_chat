require "application_system_test_case"

class UnifiedSpacesSystemTest < ApplicationSystemTestCase
  test "switching public and private views keeps one shared room row style and icon" do
    jack, eric = users(:one), users(:two)
    group = Room.create!(name: "Workspace Private Circle", kind: "private_group",
      is_private: true, owner: jack)
    group.participants.create!(user: jack, group_role: "owner")
    public_room = Room.create!(name: "Workspace Public Circle")
    public_room.joinables.create!(user: jack)

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: jack.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path
    assert_selector ".sd-spaces-switch a.is-active", text: "Public", wait: 10
    assert_selector "#rooms .sd-room-entry__title", text: public_room.name
    assert_selector "#rooms .sd-room-type svg", visible: :all
    assert_no_selector "#private-group-rooms .sd-room-entry__title", visible: true

    within ".sd-spaces-switch" do
      click_link "Private"
    end
    assert_selector ".sd-spaces-switch a.is-active", text: "Private", wait: 10
    state = page.evaluate_script(<<~JS)
      (() => {
        const panes = document.querySelector(".sd-space-panes")
        const pane = document.querySelector("#sd-private-pane")
        const row = document.querySelector("#private-group-rooms .sd-room-entry__title")
        const ancestors = []
        let el = row
        while (el && ancestors.length < 10) {
          const cs = getComputedStyle(el)
          ancestors.push({
            tag: el.tagName, id: el.id, className: String(el.className || "").slice(0, 95),
            display: cs.display, visibility: cs.visibility, hidden: el.hidden,
            width: Math.round(el.getBoundingClientRect().width), height: Math.round(el.getBoundingClientRect().height)
          })
          el = el.parentElement
        }
        return {space: panes?.dataset.spaceView, paneHidden: pane?.hidden,
          paneDisplay: pane && getComputedStyle(pane).display,
          text: row?.textContent, active: document.querySelector(".sd-spaces-switch .is-active")?.textContent,
          ancestors}
      })()
    JS
    puts "SPACE V2 DIAGNOSTIC: #{state.inspect}"
    assert_selector "#private-group-rooms .sd-room-entry__title", text: group.name
    assert_selector "#private-group-rooms .sd-room-type svg", visible: :all
    assert_selector "#private-group-rooms .sd-room-leave[aria-label='Leave #{group.name}']", visible: true
    assert_no_selector "#rooms .sd-room-entry__title", visible: true

    find("#private-group-rooms a[href='#{room_path(group)}']").click
    assert_current_path room_path(group), wait: 10
    assert_selector ".sd-spaces-switch a.is-active", text: "Private"
  end
end
