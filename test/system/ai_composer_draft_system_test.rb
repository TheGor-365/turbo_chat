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

    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel:not([hidden])", wait: 10
    assert_field "Editable working copy", with: original
    assert_no_selector "#ai-draft-panel img"
    assert_equal false, page.evaluate_script("!!window.__xss")
    assert_selector ".sd-ai-draft-presets button", count: 6
    click_button "Friendly"
    assert_selector ".sd-ai-draft-presets button[data-preset-id='friendly'][aria-pressed='true']"
    assert_selector "#ai-draft-panel", text: "Preset saved locally"
    assert_field "Editable working copy", with: original
    click_button "Reload from message"
    assert_field "Editable working copy", with: original
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

    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel", text: /Type a message first/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    fill_in "chat-text", with: "My local safe text"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "My local safe text"
    fill_in "chat-text", with: "Updated unsent text"
    assert_field "Editable working copy", with: "Updated unsent text"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "Updated unsent text"

    fill_in "chat-text", with: "x" * 5_001
    click_button "Reload from message"
    assert_selector "#ai-draft-panel", text: /up to 5,000 characters/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    find("#ai-draft-panel .sd-ai-draft-refresh").send_keys(:escape)
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: "x" * 5_001
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
    assert_equal count, room.messages.count
  end


  test "working copy applies and undoes without sending or changing reply and attachments" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    message = room.messages.create!(user: eric, body: "Please respond")
    login_user(jack)
    visit room_path(room)
    within "#message_#{message.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    fill_in "chat-text", with: "How you deals"
    fixture = Rails.root.join("test/fixtures/files/upload_note.txt")
    attach_file "message_attachments", fixture, make_visible: true
    count = room.messages.count

    click_button "Edit unsent message"
    assert_field "Editable working copy", with: "How you deals"
    fill_in "Editable working copy", with: "How are you doing?"
    assert_button "Apply to message", disabled: false
    assert_field "chat-text", with: "How you deals"
    click_button "Apply to message"
    assert_field "chat-text", with: "How are you doing?"
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal message.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_equal count, room.messages.count

    click_button "Undo applied edit"
    assert_field "chat-text", with: "How you deals"
    assert_equal count, room.messages.count
    fill_in "Editable working copy", with: "How are things going?"
    click_button "Apply to message"
    fill_in "chat-text", with: "Human typing wins"
    assert_selector "#ai-draft-panel button.sd-ai-draft-undo[hidden]", visible: :all
    assert_field "chat-text", with: "Human typing wins"
    assert_equal count, room.messages.count
  end

  test "a stale working copy cannot overwrite a newer message draft" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "First wording"
    click_button "Edit unsent message"
    fill_in "Editable working copy", with: "Proposed replacement"
    fill_in "chat-text", with: "Newer human wording"
    assert_button "Apply to message", disabled: true
    assert_selector "#ai-draft-panel", text: /Reload the copy before applying/
    assert_field "chat-text", with: "Newer human wording"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "Newer human wording"
    assert_button "Apply to message", disabled: true
  end

  test "a successful explicit Send closes stale AI preview but follows normal message path" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "Only the ordinary Send action persists this"
    click_button "Edit unsent message"
    assert_field "Editable working copy", with: "Only the ordinary Send action persists this"
    assert_difference("Message.count", 1) do
      click_button "Send"
      assert_selector "#messages-container", text: "Only the ordinary Send action persists this", wait: 15
    end
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: ""
  end
end
