require "application_system_test_case"

class AiAutomationConfigurationSystemTest < ApplicationSystemTestCase
  CONFIGURATION = 'section[data-controller="ai-automation-configuration"]'
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
    within CONFIGURATION do
      find("summary").click
      assert_selector "details[open]"
      assert_selector '[data-ai-automation-configuration-target="status"]',
        text: /Automation is off|configuration loaded/i, wait: 10
    end
  end

  test "review and summary configuration persist but cannot publish or spend" do
    sign_in users(:one)
    open_configuration
    within CONFIGURATION do
      select "Suggest, then Apply manually (not active yet)", from: "ai-automation-reply-mode"
      select "After N new messages (scheduler pending)", from: "ai-automation-summary-mode"
      fill_in "ai-automation-after-count", with: "15"
      click_button "Save configuration"
      assert_selector '[data-ai-automation-configuration-target="status"]',
        text: "Configuration saved", wait: 10
    end
    policy = AiAutomationPolicy.find_by!(user: users(:one), room: room)
    assert_equal "review", policy.reply_mode
    assert_equal "after_messages", policy.summary_mode
    assert_equal 15, policy.summary_after_messages
    assert_equal 0, room.messages.count

    open_configuration
    assert_selector "#ai-automation-reply-mode option:checked", text: "Suggest, then Apply manually (not active yet)"
    assert_selector "#ai-automation-summary-mode option:checked", text: "After N new messages (scheduler pending)"
    assert_field "ai-automation-after-count", with: "15"
    within CONFIGURATION do
      click_button "Turn off both"
      assert_selector '[data-ai-automation-configuration-target="status"]',
        text: "Configuration saved", wait: 10
    end
    assert_equal "off", policy.reload.reply_mode
    assert_equal "off", policy.summary_mode
  end

  test "reply proposal panel cannot masquerade as the automation configuration" do
    sign_in users(:one)
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    click_button "Room settings"

    within "section.sd-ai-reply-proposals" do
      find("summary").click
      assert_selector "details[open]"
      assert_selector '[data-ai-reply-proposals-target="status"]',
        text: "No saved suggestion.", wait: 10
    end

    within CONFIGURATION do
      find("summary").click
      assert_selector "details[open]"
      assert_selector '[data-ai-automation-configuration-target="status"]',
        text: /Automation is off|configuration loaded/i, wait: 10
    end
  end
end
