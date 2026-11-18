require "application_system_test_case"

class AiAutomationConfigurationSystemTest < ApplicationSystemTestCase
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

  def open_configuration
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    click_button "Room settings"
    find(".sd-ai-automation-configuration__summary").click
    assert_selector ".sd-ai-automation-configuration__fold[open]"
    assert_selector ".sd-ai-automation-configuration__status",
      text: /Automation is off|configuration loaded/i, wait: 10
  end

  test "review and summary configuration persist but cannot publish or spend" do
    sign_in users(:one)
    open_configuration
    select "Suggest, then Apply manually (not active yet)", from: "ai-automation-reply-mode"
    select "After N new messages (scheduler pending)", from: "ai-automation-summary-mode"
    fill_in "ai-automation-after-count", with: "15"
    click_button "Save configuration"
    assert_selector ".sd-ai-automation-configuration__status",
      text: "Configuration saved", wait: 10
    policy = AiAutomationPolicy.find_by!(user: users(:one), room: room)
    assert_equal "review", policy.reply_mode
    assert_equal "after_messages", policy.summary_mode
    assert_equal 15, policy.summary_after_messages
    assert_equal 0, room.messages.count

    open_configuration
    assert_selector "#ai-automation-reply-mode option:checked", text: "Suggest, then Apply manually (not active yet)"
    assert_selector "#ai-automation-summary-mode option:checked", text: "After N new messages (scheduler pending)"
    assert_field "ai-automation-after-count", with: "15"
    click_button "Turn off both"
    assert_selector ".sd-ai-automation-configuration__status",
      text: "Configuration saved", wait: 10
    assert_equal "off", policy.reload.reply_mode
    assert_equal "off", policy.summary_mode
  end
end
