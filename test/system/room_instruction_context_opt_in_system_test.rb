require "application_system_test_case"

class RoomInstructionContextOptInSystemTest < ApplicationSystemTestCase
  test "room instructions opt-in requires reviewed local sources and never sends automatically" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "What should we do with the Rails scope?")
    room.ai_instruction_revisions.create!(editor: alice, revision_number: 1,
      content: "Mark price as To confirm. Preserve Rails terms.")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      Capybara.current_session.reset!
      visit root_path
      page.driver.browser.manage.delete_all_cookies
      visit new_user_session_path
      assert_selector "input[type='email']", wait: 10
      fill_in "Email", with: alice.email
      fill_in "Password", with: "test-password-123"
      click_button "Log in"
      assert_current_path root_path, ignore_query: true, wait: 10
      visit room_path(room, ui_locale: :en)
      click_button "Edit unsent message"

      toggle = "input[data-ai-draft-target='roomInstructionToggle']"
      assert_selector toggle, visible: true
      assert_not find(toggle).checked?
      assert_button "Suggest reply with AI", disabled: false, wait: 10
      find(toggle).check
      assert_button "Suggest reply with AI", disabled: true
      assert_selector ".sd-ai-context-instruction-preview[data-open='false']", visible: :all

      # B19 removes the redundant public source selector. Preserve the
      # legacy H3 token/room-instruction consent contract in this test only
      # until D3.4 migrates it to Context Studio's canonical snapshot.
      page.execute_script(<<~JS)
        const review = document.querySelector("#ai-draft-panel .sd-ai-source-review")
        if (!review) throw new Error("Legacy H3 source contract missing")
        review.style.setProperty("display", "block", "important")
      JS
      find("#ai-draft-panel .sd-ai-source-review > summary").click
      click_button "Review sources"
      assert_selector ".sd-ai-context-instruction-preview[data-open='true']", wait: 10
      assert_selector ".sd-ai-context-instruction-preview pre",
        text: "Mark price as To confirm."
      assert_selector ".sd-ai-context-instruction-preview strong", text: "revision 1"
      assert_button "Suggest reply with AI", disabled: false
      assert_equal 1, room.messages.count

      find(toggle).uncheck
      assert_selector ".sd-ai-context-instruction-preview[data-open='false']", visible: :all
      assert_equal 1, room.messages.count
      assert_field "chat-text", with: ""
    end
  end
end
