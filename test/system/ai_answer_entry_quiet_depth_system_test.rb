require "application_system_test_case"

# Tests the actual owner's Quiet Depth composer, not the newer remote ERB.
# The visible Answer button is a provider-free S3 preview, never a Send.
class AiAnswerEntryQuietDepthSystemTest < ApplicationSystemTestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob,
      body: "Can we confirm the Rails signup acceptance criteria?")
  end

  def sign_in_owner
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
    sign_in_owner
    visit room_path(@room, ui_locale: :en)
    assert_selector ".sd-ai-answer-entry", text: "AI Answer", wait: 10
  end

  def assert_answer_status(expected)
    assert_selector ".sd-ai-answer-status", text: expected, wait: 10
  rescue Minitest::Assertion => failure
    details = page.evaluate_script(<<~JS)
      (() => {
        const root = document.querySelector('.msg-form')
        const status = document.querySelector('.sd-ai-answer-status')
        const trigger = document.querySelector('.sd-ai-answer-entry')
        return {
          statusHTML: status?.outerHTML,
          statusText: status?.textContent,
          rootControllers: root?.dataset.controller,
          copy: root?.dataset.aiAnswerEntryCopyValue?.slice(0,400),
          goalUrl: root?.dataset.aiAnswerEntryGoalUrlValue,
          consentUrl: root?.dataset.aiAnswerEntryConsentUrlValue,
          triggerTitle: trigger?.title,
          formValid: document.querySelector('form.message-composer')?.checkValidity(),
          editorVisible: !!document.querySelector('#chat-text')?.getClientRects().length
        }
      })()
    JS
    raise Minitest::Assertion, "#{failure.message}\nAI_ANSWER_DIAGNOSTIC: #{details.inspect}"
  end

  test "AI Answer is always discoverable and takes owner to personal goal setup" do
    open_room
    assert_answer_status("set your personal goal"), wait: 10
    find(".sd-ai-answer-entry").click
    assert_selector "#ai-room-settings[open]", wait: 10
    assert_selector ".sd-ai-conversation-goal__fold[open]"
    fill_in "ai-conversation-goal-purpose", with: "Clarify scope before agreeing to work"
    fill_in "ai-conversation-goal-constraints", with: "Never invent a deadline"
    fill_in "ai-conversation-goal-outcome", with: "Agree on the next check"
    click_button "Save my goal"
    assert_selector ".sd-ai-conversation-goal__status", text: "Goal saved", wait: 10
    assert_equal "Clarify scope before agreeing to work",
      AiConversationGoal.find_by!(room: @room, user: @alice).purpose
    assert_equal 1, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
    assert_answer_status("grants 0/2"), wait: 10
  end

  test "unanimous consent permits only a no-provider input preview without Send" do
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Clarify the Rails signup scope", revision: 1, active: true)
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    open_room
    assert_answer_status("input preview ready"), wait: 10
    find(".sd-ai-answer-entry").click
    assert_selector ".sd-ai-answer-result:not([hidden])",
      text: "Can we confirm the Rails signup acceptance criteria?", wait: 10
    assert_answer_status("no model, no cost, no Send")
    assert_field "chat-text", with: ""
    assert_equal 1, @room.messages.count
    assert_selector ".sd-ai-answer-privacy", text: "Automatic Send is off"
  end

  test "Answer never clears a human draft and ordinary Send still works" do
    open_room
    fill_in "chat-text", with: "My own Rails signup draft."
    find(".sd-ai-answer-entry").click
    assert_answer_status("empty message editor")
    assert_field "chat-text", with: "My own Rails signup draft."
    assert_equal 1, @room.messages.count
    within "form.message-composer" do
      find("button.composer-send").click
    end
    assert_selector ".sd-message", text: "My own Rails signup draft.", wait: 10
    assert_equal 2, @room.messages.count
    assert_equal false, @room.messages.order(:id).last.ai_assisted?
  end

  test "consent toggle only grants the logged-in actor, not another participant" do
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Ask for acceptance criteria", revision: 1, active: true)
    open_room
    find(".sd-ai-answer-entry").click
    assert_selector "#ai-room-settings[open]"
    assert_selector ".sd-ai-answer-consent__status", text: "0/2"
    within ".sd-ai-answer-consent" do
      click_button "Allow my messages in AI context"
      assert_selector ".sd-ai-answer-consent__status", text: "1/2", wait: 10
    end
    assert AiRoomContextConsent.find_by!(room: @room, user: @alice).enabled?
    assert_nil AiRoomContextConsent.find_by(room: @room, user: @bob)
    assert_equal 1, @room.messages.count
  end
end
