require "application_system_test_case"

class AiConversationGoalSystemTest < ApplicationSystemTestCase
  def sign_in(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  def open_goal_settings
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    click_button "Room settings"
    find(".sd-ai-conversation-goal__summary").click
    assert_selector ".sd-ai-conversation-goal__fold[open]"
    assert_selector ".sd-ai-conversation-goal__status", text: /No personal goal saved|Personal goal loaded/, wait: 10
  end

  test "personal goal saves only on explicit click and survives a page refresh" do
    sign_in users(:one)
    open_goal_settings
    fill_in "ai-conversation-goal-purpose", with: "Prepare to discuss a Rails project"
    fill_in "ai-conversation-goal-constraints", with: "Do not promise a price"
    fill_in "ai-conversation-goal-outcome", with: "Agree on technical next steps"
    assert_selector ".sd-ai-conversation-goal__status", text: "Unsaved personal goal"
    assert_equal 0, AiConversationGoal.count
    click_button "Save my goal"
    assert_selector ".sd-ai-conversation-goal__status", text: "Goal saved for your account", wait: 10
    assert_equal "Prepare to discuss a Rails project",
      AiConversationGoal.find_by!(user: users(:one), room: room).purpose
    assert_equal 0, room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: room).count

    open_goal_settings
    assert_field "ai-conversation-goal-purpose",
      with: "Prepare to discuss a Rails project"
    assert_field "ai-conversation-goal-constraints", with: "Do not promise a price"
    assert_selector ".sd-ai-conversation-goal__version", text: "Version 1"
  end

  test "second member cannot see another member goal; disable remains personal" do
    AiConversationGoal.create!(room: room, user: users(:one),
      purpose: "Private only to Alice", constraints: "",
      desired_outcome: "", revision: 1, active: true)
    sign_in users(:two)
    open_goal_settings
    assert_field "ai-conversation-goal-purpose", with: ""
    assert_button "Disable goal", disabled: true
    sign_in users(:one)
    open_goal_settings
    click_button "Disable goal"
    assert_selector ".sd-ai-conversation-goal__status", text: "Goal disabled", wait: 10
    assert_equal false, AiConversationGoal.find_by!(room: room, user: users(:one)).active?
    assert_equal 0, room.messages.count
  end
end
