require "application_system_test_case"

class AiReplyProposalsSystemTest < ApplicationSystemTestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "Please review the Rails signup scope")
    AiAutomationPolicy.create!(room: @room, user: @alice, reply_mode: "review")
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Clarify the project's acceptance criteria")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
      AiRoomAutomationConsent.create!(room: @room, user: user,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true)
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

  def open_proposals
    click_button "Edit unsent message"
    click_button "Room settings"
    within "section.sd-ai-reply-proposals" do
      find("summary").click
      assert_selector "details[open]", wait: 10
      assert_button "Create offline suggestion", disabled: false, wait: 10
    end
  end

  test "Apply fills the existing human composer without Send, then owner manually Sends" do
    login
    visit room_path(@room, ui_locale: :en)
    open_proposals
    within "section.sd-ai-reply-proposals" do
      click_button "Create offline suggestion"
      assert_selector ".sd-ai-automation-configuration__status",
        text: "Offline template saved", wait: 10
      assert_button "Apply to empty editor", disabled: false
      click_button "Apply to empty editor"
    end
    text = AiWorkspace::OfflineReplyProposal::TEMPLATES.fetch("en")
    assert_field "chat-text", with: text, wait: 10
    assert_equal 1, @room.messages.count
    assert_equal 0, @room.messages.where(user: @alice).count
    assert_equal 0, AiUsageReservation.count
    assert_equal "applied", AiReplyProposal.find_by!(room: @room, user: @alice).state

    find("button.composer-send").click
    assert_selector "#messages-container", text: text, wait: 10
    assert_equal 2, @room.messages.count
    sent = @room.messages.where(user: @alice).last
    assert_equal text, sent.body
    assert_equal false, sent.ai_assisted?
  end

  test "Apply refuses to overwrite any typed human draft" do
    login
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "My important unfinished draft"
    open_proposals
    within "section.sd-ai-reply-proposals" do
      click_button "Create offline suggestion"
      assert_button "Apply to empty editor", disabled: false, wait: 10
      click_button "Apply to empty editor"
      assert_selector ".sd-ai-automation-configuration__status",
        text: "not empty", wait: 10
    end
    assert_field "chat-text", with: "My important unfinished draft"
    assert_equal 1, @room.messages.count
    assert_equal "pending", AiReplyProposal.find_by!(room: @room, user: @alice).state
  end
end
