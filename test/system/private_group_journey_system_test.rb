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

    within ".sd-spaces-switch" do
      click_link "Private"
    end
    assert_selector ".sd-space-panes[data-space-view='private']"
    assert_selector ".sd-rail-section--private-groups"
    fill_in "New private group name", with: title
    within ".sd-private-group-create" do
      find("button[aria-label='Create private group']").click
    end
    # The browser POST is asynchronous; wait for the redirected group DOM
    # before querying the database from the test process.
    assert_selector "#private-group-details summary", wait: 15
    assert_selector "#private-group-details:not([open])"
    room = Room.find_by!(name: title)
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_no_selector "#public-room-directory", text: title
    assert_selector ".sd-conversation-toolbar .sd-conversation-leave[aria-label='Leave #{title}']"
    find("#private-group-details > summary").click
    assert_selector "#private-group-details[open]", text: "Jack Test"
    assert_selector "#private-group-details", text: "Invite only"

    within "#private-group-details" do
      find(".sd-private-group-invite-form button[role='combobox']").click
      find(".sd-private-group-invite-form [role='option']", text: "Eric Test").click
      find(".sd-private-group-invite-form button[aria-label='Send private group invitation']").click
    end
    # The Invite form navigates back to the same URL. Checking only the path
    # can succeed before the browser submits the POST and commits its row.
    # Wait for the response flash to prove the browser completed that request.
    find("#private-group-details > summary").click
    assert_selector "#private-group-details .sd-group-invite-feedback[role=status]",
      text: "Invitation sent", wait: 15
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
      assert_selector "#private-group-details summary", wait: 10
      find("#private-group-details > summary").click
      assert_selector "#private-group-details", text: "Eric Test", wait: 10
      assert_selector "#private-group-rooms a[href='#{room_path(room)}']", text: title
      assert_not room.reload.public_room?
      assert_selector "#private-group-rooms .sd-room-entry__title", text: title
      assert_selector "#private-group-rooms .sd-room-leave[aria-label='Leave #{title}'] svg",
        visible: :all
      within "#private-group-rooms" do
        find("form[action='#{leave_private_group_path(room)}'] button[aria-label='Leave #{title}']").click
      end
      assert_current_path rooms_path, ignore_query: true, wait: 10
      assert_no_selector "#private-group-rooms a[href='#{room_path(room)}']"
      assert_not room.reload.accessible_to?(bob)
    end
  end
end
