require "application_system_test_case"

# Quiet Depth acceptance: the single room purpose is the existing saved
# instruction revision; no duplicate goal form or extra consent card.
class AiAnswerEntryQuietDepthSystemTest < ApplicationSystemTestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob,
      body: "Can we confirm the Rails signup acceptance criteria?")
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

  def open_room
    login
    visit room_path(@room, ui_locale: :en)
    assert_selector ".composer-controls .sd-ai-answer-entry", text: "AI Answer", wait: 10
    assert_selector ".sd-quick-beautify-trigger", visible: :all
    assert_no_selector ".sd-ai-conversation-goal", visible: :all
    assert_no_selector ".sd-ai-answer-consent", visible: :all
    assert_equal "answer", page.evaluate_script("document.querySelector('.msg-form').dataset.aiComposerMode")
  end

  def grant_all
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
  end

  def save_instruction
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Clarify scope before agreeing to work")
  end

  test "missing purpose navigates to the existing room instructions and saves one revision" do
    open_room
    assert_selector ".sd-ai-answer-status", visible: :all,
      text: "save room instructions", wait: 10
    find(".composer-controls .sd-ai-answer-entry").click
    assert_selector "#ai-room-settings[open]", wait: 10
    assert_selector ".sd-room-ai-instructions__fold[open]", wait: 10
    within ".sd-room-ai-instructions" do
      fill_in "room-ai-instruction-text-#{@room.id}", with: "Clarify the Rails signup scope."
      click_button "Save version"
      assert_selector ".sd-room-ai-instructions__status",
        text: "Version saved for room members", wait: 10
    end
    assert_equal "Clarify the Rails signup scope.",
      RoomAiInstructionRevision.where(room: @room).order(:revision_number).last.content
    assert_equal 0, AiConversationGoal.where(room: @room).count
    assert_equal 1, @room.messages.count
  end

  test "saved room purpose and unanimous grant permit only provider-free preview" do
    save_instruction
    grant_all
    open_room
    assert_selector ".sd-ai-answer-status", visible: :all,
      text: "input preview ready", wait: 10
    find(".composer-controls .sd-ai-answer-entry").click
    assert_selector ".sd-ai-answer-result:not([hidden])",
      text: "Can we confirm the Rails signup acceptance criteria?", wait: 10
    assert_selector ".sd-ai-answer-result", text: "Clarify scope before agreeing to work"
    assert_equal 1, @room.messages.count
    assert_field "chat-text", with: ""
  end

  test "typed text switches to Beautify without removing the ordinary Send action" do
    open_room
    assert_selector ".composer-controls .sd-ai-answer-entry", visible: true
    assert_selector ".composer-controls .sd-quick-beautify-trigger", visible: false
    fill_in "chat-text", with: "Please clarify the Rails signup."
    assert_selector ".composer-controls .sd-quick-beautify-trigger", visible: true, wait: 10
    assert_selector ".composer-controls .sd-ai-answer-entry", visible: false
    within "form.message-composer" do
      find("button.composer-send").click
    end
    assert_selector ".sd-message", text: "Please clarify the Rails signup.", wait: 10
    assert_equal 2, @room.messages.count
    assert_equal false, @room.messages.order(:id).last.ai_assisted?
    assert_field "chat-text", with: ""
    assert_selector ".composer-controls .sd-ai-answer-entry", visible: true, wait: 10
  end

  test "existing smart replies switch is the single place to manage own context grant" do
    save_instruction
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      open_room
      find(".composer-controls .sd-ai-answer-entry").click
      assert_selector "#ai-room-settings[open]", wait: 10
      assert_selector ".sd-ai-room-option--smart", wait: 10
      within ".sd-ai-room-option--smart" do
        find("button[data-ai-draft-target='smartReplyToggle']").click
        assert_selector "button[data-ai-draft-target='smartReplyToggle'][aria-checked='true']", wait: 10
      end
      assert AiRoomContextConsent.find_by!(room: @room, user: @alice).enabled?
      assert_nil AiRoomContextConsent.find_by(room: @room, user: @bob)
      assert_equal 1, @room.messages.count
    end
  end
  test "saved template can explicitly activate a new room instruction revision" do
    open_room
    find(".composer-controls .sd-ai-answer-entry").click
    assert_selector "#ai-room-settings[open]", wait: 10
    within ".sd-room-ai-instructions" do
      fill_in "room-ai-instruction-text-#{@room.id}", with: "Clarify the first scope."
      click_button "Save version"
      assert_selector ".sd-room-ai-instructions__status",
        text: "Version saved for room members", wait: 10

      fill_in "room-ai-instruction-text-#{@room.id}", with: "Clarify the second scope."
      click_button "Save version"
      assert_selector ".sd-room-ai-instructions__revision", text: "Version 2", wait: 10

      click_button "Custom instruction templates"
      assert_selector ".sd-room-ai-instructions__history-entry", minimum: 2, wait: 10
      entry = all(".sd-room-ai-instructions__history-entry").find do |el|
        el.find("summary", visible: true).text.include?("Version 1")
      end
      assert entry, "Expected the earlier saved room instruction in the template library"
      entry.find("summary").click
      entry.click_button "Apply to room now"
      assert_selector ".sd-room-ai-instructions__revision", text: "Version 3", wait: 10
    end
    assert_equal "Clarify the first scope.",
      RoomAiInstructionRevision.where(room: @room).order(:revision_number).last.content
    assert_equal 1, @room.messages.count
  end


end
