require "application_system_test_case"

class ProfileLabelsSystemTest < ApplicationSystemTestCase
  test "renaming a DM member updates open peer and own browser sessions without reload" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Message sent under old label")

    login_as_browser(alice)
    visit room_path(room)
    assert_selector 'nav[data-profile-labels-connected="true"]', wait: 15
    assert_selector '#single_room h4', text: bob.chat_label
    assert_selector '#messages-container .name', text: bob.chat_label

    Capybara.using_session(:profile_bob_other_tab) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector 'nav[data-profile-labels-connected="true"]', wait: 15
    end

    Capybara.using_session(:profile_bob_settings) do
      login_as_browser(bob)
      visit edit_user_registration_path
      fill_in "Display name (optional)", with: "  Eric Live  "
      fill_in "Current password", with: "test-password-123"
      click_button "Save changes"
      assert_current_path root_path, ignore_query: true, wait: 10
      assert_equal "Eric Live", bob.reload.display_name
    end

    # Neither browser revisits or reloads the room.
    assert_selector '#single_room h4', text: "Eric Live", wait: 15
    assert_selector '#messages-container .name', text: "Eric Live", wait: 15
    assert_selector '#users', text: "Eric Live", wait: 15
    assert_selector '#direct-rooms', text: "Eric Live", wait: 15

    Capybara.using_session(:profile_bob_other_tab) do
      assert_selector 'nav[aria-label="Main navigation"] [data-profile-label-user-id]', text: "Eric Live", wait: 15
      assert_selector ".sd-nav__account .sd-nav__identity", text: "Eric Live", wait: 15
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
