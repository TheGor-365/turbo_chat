require "application_system_test_case"

class RoomAiWorkspaceSystemTest < ApplicationSystemTestCase
  test "room-local AI opens from conversation and reviews selected texts without generating" do
    jack, eric = users(:one), users(:two)
    room = Room.create_private_room([jack, eric],
      "private_#{[jack.id, eric.id].sort.join('_')}")
    chosen = room.messages.create!(user: jack, body: "Offline AI selection first point")
    skipped = room.messages.create!(user: eric, body: "Offline AI selection unselected")
    second = room.messages.create!(user: jack, body: "Offline AI selection final point")

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: jack.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    visit room_path(room)
    assert_selector "#single_room", wait: 10
    find("a.sd-ai-entry[aria-label='Chat history AI — selected messages only (offline)']").click
    assert_current_path room_ai_workspace_path(room), wait: 10
    assert_selector "#ai-workspace .sd-ai-status", text: "AI is not configured"
    assert_selector "#ai-workspace .sd-ai-message-choice", count: 3
    assert_selector "#review_preset_id option", count: 6, visible: false
    assert_selector "#ai-generate-unavailable[disabled]", text: "Generate unavailable"
    check "ai-message-#{chosen.id}"
    check "ai-message-#{second.id}"
    assert_selector "[data-ai-selection-target=counter]", text: "2 / 8 selected"
    click_button "Review selected scope"
    assert_selector "#ai-scope-review", text: "Offline AI selection first point", wait: 10
    assert_selector "#ai-scope-review", text: "Offline AI selection final point"
    assert_no_selector "#ai-scope-review", text: skipped.body
    assert_selector "#ai-scope-review", text: "No AI response was generated or requested"
    assert_selector "#ai-preset-review", text: "Technical Summary"

    visit room_ai_workspace_path(room)
    find("button[aria-controls='review_operation-options']").click
    find("#review_operation-options [role='option']", text: "Polish text").click
    assert_selector "#review_preset_id option[value='friendly']:not([disabled])", visible: false
    find("button[aria-controls='review_preset_id-options']").click
    find("#review_preset_id-options [role='option']", text: "Friendly").click
    check "ai-message-#{chosen.id}"
    click_button "Review selected scope"
    assert_selector "#ai-preset-review", text: "Friendly"
    assert_selector "#ai-scope-review", text: "No AI response was generated or requested"
    find("a.sd-ai-back").click
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector "#single_room"
  end
end
