require "application_system_test_case"

class AiGenerationPreviewSystemTest < ApplicationSystemTestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "Can you clarify the Rails signup form?")
    AiConversationGoal.create!(user: @alice, room: @room,
      purpose: "Clarify the scope of the signup change", revision: 1)
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
  end

  def login
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: @alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def open_preview
    click_button "Edit unsent message"
    click_button "Room settings"
    within "section.sd-ai-generation-preview" do
      find("summary").click
      assert_selector "details[open]"
    end
  end

  test "AI Answer input preview shows only permitted data and never sends" do
    login
    visit room_path(@room, ui_locale: :en)
    open_preview
    within "section.sd-ai-generation-preview" do
      click_button "Check AI Answer (dry-run)"
      assert_selector "[data-ai-generation-preview-target='status']",
        text: "Prepared locally", wait: 10
      assert_selector "[data-ai-generation-preview-target='result']",
        text: "Can you clarify the Rails signup form?", wait: 10
      assert_selector "[data-ai-generation-preview-target='result']",
        text: "Clarify the scope of the signup change"
    end
    assert_field "chat-text", with: ""
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count
  end

  test "Beautify input preview never replaces a human draft or sends" do
    login
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "pls clarify rails scope."
    open_preview
    within "section.sd-ai-generation-preview" do
      click_button "Check Beautify (dry-run)"
      assert_selector "[data-ai-generation-preview-target='status']",
        text: "Prepared locally", wait: 10
      assert_selector "[data-ai-generation-preview-target='result']",
        text: "pls clarify rails scope.", wait: 10
      click_button "Check AI Answer (dry-run)"
      assert_selector "[data-ai-generation-preview-target='status']",
        text: "empty editor", wait: 10
    end
    assert_field "chat-text", with: "pls clarify rails scope."
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count
  end
end
