require "application_system_test_case"

class RoomAiInstructionsSystemTest < ApplicationSystemTestCase
  def login(user)
    # Parallel/named Chrome sessions can survive adjacent examples in CI.
    # Always explicitly reset the browser identity before signing in.
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    # Keep the global browser library from leaking between isolated test cases.
    page.execute_script("localStorage.removeItem(arguments[0])",
      "turbo-chat:room-instruction-templates:v2:user:#{user.id}")
  end

  test "room instructions save with revision history, never sending the unsent message" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    login alice
    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "This chat message must stay unsent."
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    find(".sd-room-ai-instructions__summary").click
    assert_selector ".sd-room-ai-instructions__fold:not([open])"
    find(".sd-room-ai-instructions__summary").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    assert_selector ".sd-room-ai-instructions__save:disabled"
    find(".sd-room-ai-instructions__textarea").fill_in with:
      "Rails 8. Price and deadline NOT agreed."
    assert_selector ".sd-room-ai-instructions__save:not(:disabled)"
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status",
      text: "Version saved for room members", wait: 10
    assert_equal 1, room.ai_instruction_revisions.count
    assert_field "room-ai-instruction-text-#{room.id}", with: ""
    assert_selector ".sd-room-ai-instructions__save:disabled"
    assert_selector ".sd-room-ai-instructions__current[open] pre",
      text: "Price and deadline NOT agreed."
    assert_field "chat-text", with: "This chat message must stay unsent."
    assert_equal 0, room.messages.count
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-shell[data-open='true']"
    assert_selector ".sd-room-ai-instructions__history-entry", count: 1
    animation = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector('.sd-room-ai-instructions__history-shell'))
        .transitionProperty
    JS
    assert_includes animation, "grid-template-rows"
    find(".sd-room-ai-instructions__history-entry summary").click
    assert_selector ".sd-room-ai-instructions__history-entry pre",
      text: "Price and deadline NOT agreed."

    find(".sd-room-ai-instructions__textarea").fill_in with: "Second version."
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status",
      text: "Version saved for room members", wait: 10
    assert_equal 2, room.ai_instruction_revisions.count
    assert_field "room-ai-instruction-text-#{room.id}", with: ""
    assert_selector ".sd-room-ai-instructions__current[open] pre",
      text: "Second version."
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry", count: 2
    assert_equal 0, room.messages.count
  end

  test "saved version is a deliberate full replacement; stale revision keeps user's unsaved text" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.ai_instruction_revisions.create!(editor: alice, revision_number: 1,
      content: "Full original instructions.")
    login alice
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    assert_field "room-ai-instruction-text-#{room.id}", with: ""
    assert_selector ".sd-room-ai-instructions__current", text: "Active room instruction"
    assert_selector ".sd-room-ai-instructions__save:disabled"

    find(".sd-room-ai-instructions__current > summary").click
    click_button "Edit saved version"
    assert_field "room-ai-instruction-text-#{room.id}", with: "Full original instructions."
    find(".sd-room-ai-instructions__textarea").fill_in with: "My revised requirements."
    room.ai_instruction_revisions.create!(editor: bob, revision_number: 2,
      content: "Other member's competing edit.")
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__conflict[data-open='true']",
      text: "Another member changed", wait: 10
    assert_field "room-ai-instruction-text-#{room.id}", with: "My revised requirements."
    assert_equal 2, room.ai_instruction_revisions.count

    click_button "Keep my text; base on latest revision"
    assert_field "room-ai-instruction-text-#{room.id}", with: "My revised requirements."
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status",
      text: "Version saved for room members", wait: 10
    assert_equal 3, room.ai_instruction_revisions.count
    assert_field "room-ai-instruction-text-#{room.id}", with: ""
    assert_selector ".sd-room-ai-instructions__save:disabled"
    assert_equal "My revised requirements.", room.ai_instruction_revisions.last.content
  end

  test "pasted instructions grow and saved revision rename persists without new revision" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    login alice
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    # B16 keeps the canonical recipient avatars in Room, not a duplicated
    # room-context header inside the Instructions editor. Verify both views.
    find("#ai-room-settings .sd-workspace-tabs button[data-workspace-tab='room']").click
    assert_selector "#ai-room-settings[data-view='room'] .sd-ai-room-context .sd-ai-inline-avatars > *", minimum: 2
    find("#ai-room-settings .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[data-view='instructions'] .sd-room-ai-instructions__fold[open]"
    original_height = page.evaluate_script(
      "document.querySelector('.sd-room-ai-instructions__textarea').getBoundingClientRect().height")
    long_text = (["The deadline and budget are not confirmed."] * 35).join(" ")
    find(".sd-room-ai-instructions__textarea").fill_in with: long_text
    assert_selector ".sd-room-ai-instructions__save:not(:disabled)"
    assert_operator page.evaluate_script(
      "document.querySelector('.sd-room-ai-instructions__textarea').scrollHeight"), :>, original_height
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status",
      text: "Version saved for room members", wait: 10
    assert_equal 1, room.ai_instruction_revisions.count
    click_button "Edit saved version"
    assert_selector ".sd-room-ai-instructions__save:disabled"
    find(".sd-room-ai-instructions__inline-name").fill_in with: "Verified project brief"
    find(".sd-room-ai-instructions__inline-name").send_keys(:tab)
    assert_selector ".sd-room-ai-instructions__status", text: "Name saved on this device"
    assert_selector ".sd-room-ai-instructions__save:disabled"
    assert_equal 1, room.ai_instruction_revisions.count
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry", text: "Verified project brief"
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry", text: "Verified project brief"
    assert_equal 1, room.ai_instruction_revisions.count
  end

  test "group member reads history but cannot edit instructions or enable AI" do
    alice, bob = users(:one), users(:two)
    group = Room.create!(name: "InstructionsSystemGroup", is_private: true,
      kind: "private_group", owner: alice)
    group.participants.create!(user: alice, group_role: "owner")
    group.participants.create!(user: bob, group_role: "member")
    group.ai_instruction_revisions.create!(editor: alice,
      revision_number: 1, content: "Use proposal, no confirmed cost.")
    login bob
    visit room_path(group, ui_locale: :en)
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    assert_selector ".sd-room-ai-instructions__textarea[readonly][hidden]", visible: :all
    assert_no_selector ".sd-room-ai-instructions__save", visible: :all
    assert_no_selector ".sd-room-ai-instructions__scope"
    assert_selector ".sd-room-ai-instructions__current", text: "Active room instruction"
    find(".sd-room-ai-instructions__current > summary").click
    assert_selector ".sd-room-ai-instructions__current pre", text: "Use proposal, no confirmed cost."
    assert_no_selector ".sd-room-ai-instructions__current button", visible: :all
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry", count: 1
    assert_equal 0, group.messages.count
  end


  test "renamed room revision becomes a reusable template in another room with explicit Save" do
    alice, bob = users(:one), users(:two)
    source = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    destination = Room.create!(name: "ReusableInstructionsTarget", is_private: true,
      kind: "private_group", owner: alice)
    destination.participants.create!(user: alice, group_role: "owner")
    destination.participants.create!(user: bob, group_role: "member")
    login alice
    visit room_path(source, ui_locale: :en)
    fill_in "chat-text", with: "Keep this chat draft unsent."
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"

    # Auto-generated naming is a placeholder, not editable text that may
    # reappear while Selenium clears/retypes on a slower Chrome runner.
    assert_field "room-ai-instruction-name-#{source.id}", with: ""
    assert_equal "Instruction #1",
      find(".sd-room-ai-instructions__inline-name")[:placeholder]
    find(".sd-room-ai-instructions__inline-name").fill_in with: "Project scope rules"
    assert_field "room-ai-instruction-name-#{source.id}", with: "Project scope rules"
    find(".sd-room-ai-instructions__inline-name").send_keys(:tab)
    assert_field "room-ai-instruction-name-#{source.id}", with: "Project scope rules"
    find(".sd-room-ai-instructions__textarea").fill_in with: "Rails scope and acceptance."
    assert_equal 0, source.ai_instruction_revisions.count
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status", text: "Version saved for room members", wait: 10
    assert_equal 1, source.ai_instruction_revisions.count
    assert_equal 0, source.messages.count
    assert_field "chat-text", with: "Keep this chat draft unsent."

    visit room_path(destination, ui_locale: :en)
    fill_in "chat-text", with: "Still unsent in second room."
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-workspace-tabs button[data-workspace-tab='instructions']").click
    assert_selector ".sd-room-ai-instructions__fold[open]"
    assert_field "room-ai-instruction-text-#{destination.id}", with: ""
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry",
      text: "Project scope rules", count: 1
    find(".sd-room-ai-instructions__history-entry > summary").click
    assert_selector ".sd-room-ai-instructions__history-entry pre",
      text: "Rails scope and acceptance."
    click_button "Load into draft"
    assert_field "room-ai-instruction-text-#{destination.id}", with: "Rails scope and acceptance."
    assert_field "room-ai-instruction-name-#{destination.id}", with: "Project scope rules"
    assert_equal 0, destination.ai_instruction_revisions.count
    assert_field "chat-text", with: "Still unsent in second room."

    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status", text: "Version saved for room members", wait: 10
    assert_equal "Rails scope and acceptance.", destination.ai_instruction_revisions.last.content
    assert_equal 1, destination.ai_instruction_revisions.count
    assert_equal 0, destination.messages.count
  end

end
