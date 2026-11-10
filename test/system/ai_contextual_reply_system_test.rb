require "application_system_test_case"
require "minitest/mock"

class AiContextualReplySystemTest < ApplicationSystemTestCase
  def login_as(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  test "one click contextual suggestion uses authorized sources but needs Apply and separate Send" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Can you send the proposal?")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    suggestion = "Could you confirm which proposal version you need?"

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_as(alice)
      visit room_path(room)
      click_button "Edit unsent message"
      assert_button "Suggest reply with Grok", disabled: false, wait: 10
      page.execute_script(<<~JS)
        window.__h3gCount = 0
        window.__h3gFetch = window.fetch
        window.fetch = async (url, options) => {
          if (String(url).includes("/ai/reply")) {
            window.__h3gCount += 1
            window.__h3gPayload = JSON.parse(options.body)
            return { ok: true, json: async () => ({
              text: #{suggestion.to_json},
              cost_usd: "0.000208",
              source_message_ids: [#{incoming.id}],
              omitted_context_messages: 0
            }) }
          }
          return window.__h3gFetch(url, options)
        }
      JS
      assert_equal 0, room.messages.where(user: alice).count
      click_button "Suggest reply with Grok"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /Suggested reply/
      assert_equal "1", page.evaluate_script("window.__h3gPayload.reply.consent")
      assert_equal "", page.evaluate_script("window.__h3gPayload.reply.hint")
      assert_equal 1, page.evaluate_script("window.__h3gCount")
      assert_field "Editable working copy", with: suggestion
      assert_field "chat-text", with: ""
      assert_equal 0, room.messages.where(user: alice).count
      assert_button "Apply to message", disabled: false
      click_button "Apply to message"
      assert_field "chat-text", with: suggestion
      assert_equal 0, room.messages.where(user: alice).count
      assert_button "Undo applied AI edit"
      click_button "Undo applied AI edit"
      assert_field "chat-text", with: ""
      assert_equal 0, room.messages.where(user: alice).count
    end
  end

  test "one participant's consent never makes contextual reply available" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Please send an update.")
    AiRoomContextConsent.find_or_initialize_by(room: room, user: alice).grant!
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_as(alice)
      visit room_path(room)
      click_button "Edit unsent message"
      within "#ai-draft-panel" do
        click_button "Room settings"
      end
      assert_selector "#ai-room-settings [data-ai-draft-target='smartReplyStatus']",
        text: /Awaiting other participants/, wait: 10
      click_button "Edit draft"
      assert_no_button "Suggest reply with Grok"
    end
  end

  test "five contextual tasks are selectable but only a chosen task starts one explicit request" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Can you summarize the deliverables?")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    suggestion = "Deliverables: scope review [M#{incoming.id}]."

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        click_button "Edit unsent message"
        assert_selector "#ai-draft-panel .sd-ai-context-task-controls:not([hidden])", wait: 10
      assert_button "Generate with Grok", disabled: true
      select "Client brief", from: "ai-context-task-kind"
      assert_button "Generate with Grok", disabled: false
      page.execute_script(<<~JS)
        window.__taskCalls = 0
        window.__oldFetch = window.fetch
        window.fetch = async (url, options) => {
          if (String(url).includes("/ai/task")) {
            window.__taskCalls += 1
            window.__taskPayload = JSON.parse(options.body)
            return { ok: true, json: async () => ({
              text: #{suggestion.to_json},
              kind: "client_brief", cost_usd: "0.000238",
              source_message_ids: [#{incoming.id}],
              omitted_context_messages: 0
            }) }
          }
          return window.__oldFetch(url, options)
        }
      JS
      click_button "Generate with Grok"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /Context task/
      assert_equal "client_brief", page.evaluate_script("window.__taskPayload.task.kind")
      assert_equal "1", page.evaluate_script("window.__taskPayload.task.consent")
      assert_equal 1, page.evaluate_script("window.__taskCalls")
      assert_field "Editable working copy", with: suggestion
      assert_field "chat-text", with: ""
      assert_equal 0, room.messages.where(user: alice).count
      click_button "Apply to message"
      assert_field "chat-text", with: suggestion
      assert_equal 0, room.messages.where(user: alice).count
      end
    end
  end
end
