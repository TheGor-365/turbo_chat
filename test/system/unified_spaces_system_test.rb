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
    assert_field "New public room name"
    assert_field "Search public rooms"
    assert_no_selector "#private-group-rooms .sd-room-entry__title", visible: true

    within ".sd-spaces-switch" do
      click_link "Private"
    end
    assert_selector ".sd-spaces-switch a.is-active", text: "Private", wait: 10
    assert_selector "#private-group-rooms .sd-room-entry__title", text: group.name
    assert_selector "#private-group-rooms .sd-room-type svg", visible: :all
    assert_field "New private group name"
    assert_field "Search private rooms"
    assert_selector "#private-group-rooms .sd-room-leave[aria-label='Leave #{group.name}']", visible: true
    assert_no_selector "#rooms .sd-room-entry__title", visible: true

    find("#private-group-rooms a[href='#{room_path(group)}']").click
    assert_current_path room_path(group), wait: 10
    assert_selector ".sd-spaces-switch a.is-active", text: "Private"
  end

  test "non-admin creates public room through icon-first UI and can search their own private groups" do
    jack = users(:one)
    jack.update!(role: :user)
    existing = Room.create!(name: "My Searchable Project Circle",
      kind: "private_group", is_private: true, owner: jack)
    existing.participants.create!(user: jack, group_role: "owner")
    Room.create!(name: "Another Person Private Circle", kind: "private_group",
      is_private: true, owner: users(:two)).tap do |room|
      room.participants.create!(user: users(:two), group_role: "owner")
    end

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

    public_title = "Browser Public Circle #{SecureRandom.hex(3)}"
    fill_in "New public room name", with: public_title
    find("#sd-public-pane button[aria-label='Create public room']").click
    assert_selector "#single_room", text: public_title, wait: 15
    room = Room.find_by!(name: public_title)
    assert room.public_room?
    assert_equal jack.id, room.owner_id

    within ".sd-spaces-switch" do
      click_link "Private"
    end
    assert_field "Search private rooms", wait: 10
    fill_in "Search private rooms", with: "Searchable Project"
    assert_selector "#private_search_results", text: existing.name, wait: 15
    assert_no_selector "#private_search_results", text: "Another Person Private Circle"
    find("#private_search_results a[href='#{room_path(existing)}']").click
    assert_current_path room_path(existing), ignore_query: true, wait: 15
  end
end
