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
    click_button "Room settings"
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
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click
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
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click
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
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click

    find(".sd-room-ai-instructions__name-edit").click
    find(".sd-room-ai-instructions__name-actions input").fill_in with: "Project scope rules"
    find(".sd-room-ai-instructions__name-save").click
    assert_selector ".sd-room-ai-instructions__draft-name", text: "Project scope rules"
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
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click
    assert_field "room-ai-instruction-text-#{destination.id}", with: ""
    click_button "Custom instruction templates"
    assert_selector ".sd-room-ai-instructions__history-entry",
      text: "Project scope rules", count: 1
    find(".sd-room-ai-instructions__history-entry > summary").click
    assert_selector ".sd-room-ai-instructions__history-entry pre",
      text: "Rails scope and acceptance."
    click_button "Load into draft"
    assert_field "room-ai-instruction-text-#{destination.id}", with: "Rails scope and acceptance."
    assert_selector ".sd-room-ai-instructions__draft-name", text: "Project scope rules"
    assert_equal 0, destination.ai_instruction_revisions.count
    assert_field "chat-text", with: "Still unsent in second room."

    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status", text: "Version saved for room members", wait: 10
    assert_equal "Rails scope and acceptance.", destination.ai_instruction_revisions.last.content
    assert_equal 1, destination.ai_instruction_revisions.count
    assert_equal 0, destination.messages.count
  end


  test "renaming unchanged saved instruction persists without another revision and paste grows editor" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    login alice
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click
    fill_in "room-ai-instruction-text-#{room.id}", with: "Keep terms and error codes."
    click_button "Save version"
    assert_selector ".sd-room-ai-instructions__status",
      text: "Version saved for room members", wait: 10
    assert_equal 1, room.ai_instruction_revisions.count

    click_button "Edit saved version"
    assert_field "room-ai-instruction-text-#{room.id}", with: "Keep terms and error codes."
    assert_selector ".sd-room-ai-instructions__save:disabled"
    assert_selector ".sd-room-ai-instructions__name-caption", text: "Template name:"
    find(".sd-room-ai-instructions__name-edit").click
    fill_in "Template name", with: "Rails order incident playbook"
    click_button "Save name"
    assert_selector ".sd-room-ai-instructions__status", text: "Name saved on this device"
    assert_selector ".sd-room-ai-instructions__current-name", text: "Rails order incident playbook"
    assert_equal 1, room.ai_instruction_revisions.count
    assert_equal 0, room.messages.count

    baseline = page.evaluate_script(
      "parseFloat(document.querySelector('.sd-room-ai-instructions__textarea').style.height)")
    page.execute_script(<<~JS)
      const editor = document.querySelector('.sd-room-ai-instructions__textarea')
      editor.value = Array.from({length: 18}, (_, i) => 'Rule ' + i + ': verified source').join('\\n')
      editor.dispatchEvent(new Event('input', {bubbles:true}))
    JS
    assert_selector ".sd-room-ai-instructions__textarea[style*='height']", wait: 10
    assert_operator page.evaluate_script(
      "parseFloat(document.querySelector('.sd-room-ai-instructions__textarea').style.height)"),
      :>, baseline

    # A plain browser reload must preserve the title without affecting room text.
    visit room_path(room, ui_locale: :en)
    click_button "Edit unsent message"
    click_button "Room settings"
    find(".sd-room-ai-instructions__summary").click
    assert_selector ".sd-room-ai-instructions__current-name",
      text: "Rails order incident playbook"
    assert_equal 1, room.ai_instruction_revisions.count
    assert_equal "Keep terms and error codes.", room.ai_instruction_revisions.last.content
  end
end
