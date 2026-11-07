require "application_system_test_case"

class PrivateGroupJourneySystemTest < ApplicationSystemTestCase
  test "creator invites an existing person and invitee accepts into a private group" do
    alice, bob = users(:one), users(:two)
    alice.update!(display_name: "Jack Test")
    bob.update!(display_name: "Eric Test")
    title = "Design Circle #{SecureRandom.hex(3)}"

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path

    assert_selector ".sd-rail-section--private-groups"
    fill_in "New private group name", with: title
    within ".sd-private-group-create" do
      click_button "Create"
    end
    # The browser POST is asynchronous; wait for the redirected group DOM
    # before querying the database from the test process.
    assert_selector "#private-group-details", text: "Jack Test", wait: 15
    room = Room.find_by!(name: title)
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector "#private-group-details", text: "invite only"
    assert_no_selector "#public-room-directory", text: title

    within "#private-group-details" do
      select "Eric Test", from: "Invite a person"
      click_button "Invite"
    end
    assert_current_path room_path(room), ignore_query: true, wait: 10
    invite = PrivateGroupInvitation.find_by!(room: room, user: bob)
    assert_equal "pending", invite.status
    assert_not room.accessible_to?(bob)

    Capybara.using_session(:private_group_invitee) do
      visit root_path
      page.driver.browser.manage.delete_all_cookies
      visit new_user_session_path
      assert_field "Email", wait: 10
      fill_in "Email", with: bob.email
      fill_in "Password", with: "test-password-123"
      click_button "Log in"
      assert_current_path root_path, ignore_query: true, wait: 10
      visit rooms_path
      assert_selector "#private-group-invitations", text: title, wait: 15
      assert_no_selector "#private-group-rooms a[href='#{room_path(room)}']"
      within "#private-group-invitations" do
        click_button "Accept"
      end
      assert_current_path room_path(room), ignore_query: true, wait: 15
      assert_selector "#private-group-details", text: "Eric Test", wait: 10
      assert_selector "#private-group-rooms a[href='#{room_path(room)}']", text: title
      assert_not room.reload.public_room?
    end
  end
end
