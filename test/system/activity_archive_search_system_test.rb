require "application_system_test_case"

class ActivityArchiveSearchSystemTest < ApplicationSystemTestCase
  test "archive finds a message and attachment by query then opens exact conversation context" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: alice, body: "Roadmap milestone alpha-search-27")
    file_message = room.messages.create!(user: alice, body: "Attachment for review")
    file_message.attachments.attach(io: StringIO.new("planning notes"),
      filename: "alpha-search-27-plan.txt", content_type: "text/plain")

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: bob.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    visit notifications_path
    assert_selector "#archive-search", wait: 10
    assert_selector ".sd-archive-kinds a", text: "Images"
    fill_in "Search messages or filenames", with: "alpha-search-27"
    click_button "Search archive"
    assert_selector "#archive-results [data-archive-message-id='#{message.id}']", wait: 15
    assert_selector "#archive-results [data-archive-message-id='#{file_message.id}']", wait: 10

    within ".sd-archive-kinds" do
      click_link "Files"
    end
    assert_selector "#archive-results [data-archive-message-id='#{file_message.id}']", wait: 10
    assert_no_selector "#archive-results [data-archive-message-id='#{message.id}']"
    find("#archive-results [data-archive-message-id='#{file_message.id}'] a[aria-label='Open message in context']").click
    assert_current_path room_path(room, focus: file_message.id), wait: 10
    assert_selector "#message_#{file_message.id}", text: "Attachment for review"
    assert_selector "#single_room"
  end
end
