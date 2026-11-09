require "application_system_test_case"

class AiComposerDraftSystemTest < ApplicationSystemTestCase
  def login_user(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def dm_for(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "offline AI panel never sends, renders input inertly, and preserves draft reply and file" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    parent = room.messages.create!(user: eric, body: "A message to reply to")
    login_user(jack)
    visit room_path(room)
    within "#message_#{parent.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    original = "Review my <img src=x onerror=alert(1)> draft"
    fill_in "chat-text", with: original
    fixture = Rails.root.join("test/fixtures/files/upload_note.txt")
    attach_file "message_attachments", fixture, make_visible: true
    assert_selector ".composer-preview", text: "upload_note.txt"
    original_reply = find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_equal parent.id.to_s, original_reply
    count = room.messages.count

    click_button "Review your draft offline"
    assert_selector "#ai-draft-panel:not([hidden])", wait: 10
    assert_selector ".sd-ai-draft-snapshot", text: original
    assert_no_selector "#ai-draft-panel img"
    assert_equal false, page.evaluate_script("!!window.__xss")
    assert_selector ".sd-ai-draft-presets button", count: 6
    click_button "Friendly"
    assert_selector ".sd-ai-draft-presets button[data-preset-id='friendly'][aria-pressed='true']"
    assert_selector "#ai-draft-panel", text: "Preset changed"
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    click_button "Review current draft"
    assert_selector "#ai-draft-panel .sd-ai-draft-snapshot", text: original
    assert_field "chat-text", with: original
    assert_equal original_reply, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal "upload_note.txt", page.evaluate_script("document.querySelector('#message_attachments').files[0].name")
    assert_equal count, room.messages.count

    click_button "Close draft review"
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: original
    assert_equal original_reply, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
    assert_equal count, room.messages.count
  end

  test "empty and oversized drafts fail closed; editing invalidates preview and Escape restores focus" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    count = room.messages.count

    click_button "Review your draft offline"
    assert_selector "#ai-draft-panel", text: /Enter your own message text/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    fill_in "chat-text", with: "My local safe text"
    click_button "Review current draft"
    assert_selector ".sd-ai-draft-snapshot", text: "My local safe text"
    fill_in "chat-text", with: "Updated unsent text"
    assert_selector "#ai-draft-panel", text: /Draft changed/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    click_button "Review current draft"
    assert_selector ".sd-ai-draft-snapshot", text: "Updated unsent text"

    fill_in "chat-text", with: "x" * 5_001
    click_button "Review current draft"
    assert_selector "#ai-draft-panel", text: /up to 5,000 characters/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    find("#ai-draft-panel .sd-ai-draft-refresh").send_keys(:escape)
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: "x" * 5_001
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
    assert_equal count, room.messages.count
  end

  test "a successful explicit Send closes stale AI preview but follows normal message path" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "Only the ordinary Send action persists this"
    click_button "Review your draft offline"
    assert_selector ".sd-ai-draft-snapshot", text: "Only the ordinary Send action persists this"
    assert_difference("Message.count", 1) do
      click_button "Send"
      assert_selector "#messages-container", text: "Only the ordinary Send action persists this", wait: 15
    end
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: ""
  end
end
