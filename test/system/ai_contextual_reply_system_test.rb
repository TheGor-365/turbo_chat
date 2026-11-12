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

  test "Client Brief recovers once in same browser tab after reload with fresh consent" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Rails checkout returns 422")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end
    brief = "## Objective\n- Diagnose Rails checkout HTTP 422 [M#{incoming.id}]\n" \
      "## Requirements\n- Inspect Order validation [M#{incoming.id}]"
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room, ai_task: "client_brief")
        assert_selector "#ai-draft-panel:not([hidden])", wait: 10
        assert_button "Generate with Grok", disabled: true
        page.execute_script(<<~JS)
          window.__recoverCalls = 0
          const realFetch = window.fetch.bind(window)
          window.fetch = async (url, options) => {
            if (String(url).includes("/ai/task")) {
              window.__recoverCalls += 1
              return { ok: true, json: async () => ({
                text: #{brief.to_json}, kind: "client_brief",
                cost_usd: "0.001119", source_message_ids: [#{incoming.id}],
                omitted_context_messages: 0
              }) }
            }
            return realFetch(url, options)
          }
        JS
        check "Authorize one paid Client Brief request"
        click_button "Generate with Grok"
        assert_field "Editable working copy", with: brief
        assert_equal 1, page.evaluate_script("window.__recoverCalls")
        assert_equal 0, room.messages.where(user: alice).count
        assert page.evaluate_script(<<~JS)
          Object.keys(sessionStorage).some(k => k.includes("h4-brief-v1"))
        JS

        visit room_path(room)
        assert_selector "#ai-draft-panel:not([hidden])", wait: 10
        assert_field "Editable working copy", with: brief, wait: 10
        assert_text "Recovered Client Brief from this browser tab"
        # The cost UI is conditional on manual Grok mode, which CI disables.
        # The one-tab snapshot itself must retain the actual reported cost.
        assert_equal "0.001119", page.evaluate_script(<<~JS)
          JSON.parse(sessionStorage.getItem(
            Object.keys(sessionStorage).find(k => k.includes("h4-brief-v1"))
          )).cost
        JS
        assert_button "Generate with Grok", disabled: true
        assert_equal 0, room.messages.where(user: alice).count

        AiRoomContextConsent.find_by!(room: room, user: bob).revoke!
        visit room_path(room)
        assert_no_field "Editable working copy", with: brief, wait: 10
        assert page.evaluate_script(<<~JS)
          !Object.keys(sessionStorage).some(k => k.includes("h4-brief-v1"))
        JS
      end
    end
  end

  test "AI Workspace deep link opens Client Brief editor without a model request or spend consent" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Can you help investigate HTTP 422?")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_ai_workspace_path(room)
        assert_selector "a[aria-label='Open Client Brief generation editor']"
        assert_equal 1, Message.where(room: room).count
        find("a[aria-label='Open Client Brief generation editor']").click
        assert_current_path room_path(room, ai_task: "client_brief"),
          ignore_query: false, wait: 10
        assert_selector "#ai-draft-panel:not([hidden])", wait: 10
        assert_selector "#ai-draft-panel .sd-ai-task-picker-trigger",
          text: "Client brief"
        assert_unchecked_field "Authorize one paid Client Brief request", visible: :all
        assert_button "Generate with Grok", disabled: true
        assert_equal 1, Message.where(room: room).count
      end
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
      assert_button "Suggest reply with Grok", disabled: true
      assert_selector "#ai-draft-panel [data-ai-draft-target='contextAvailability']",
        text: /Awaiting consent from every current participant/
    end
  end

  test "public room explains contextual restrictions but keeps manual draft available" do
    alice = users(:one)
    room = Room.create!(name: "Public AI restrictions", is_private: false)
    room.joinables.create!(user: alice)
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
          login_as(alice)
          visit room_path(room)
          fill_in "chat-text", with: "A public-room test draft."
          click_button "Edit unsent message"
          assert_selector "#ai-draft-panel .sd-ai-context-unavailable",
            text: /This is a public room/
          assert_no_selector "#ai-draft-panel [data-ai-draft-target='replyButton']", visible: :all
          assert_no_selector "#ai-draft-panel [data-ai-draft-target='taskControls']", visible: :all
          assert_selector "#ai-draft-panel .sd-ai-manual-generate"
          within "#ai-draft-panel" do
            click_button "Room settings"
          end
          assert_selector "#ai-room-settings .sd-ai-context-unavailable",
            text: /This is a public room/
          assert_no_selector "#ai-room-settings [data-ai-draft-target='smartReplyToggle']", visible: :all
          assert_equal 0, room.messages.count
        end
      end
    end
  end

  test "solo private group explains why contextual AI cannot run" do
    alice = users(:one)
    room = Room.create!(name: "Solo AI group", kind: "private_group",
      is_private: true, owner: alice)
    room.participants.create!(user: alice, group_role: "owner")

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        click_button "Edit unsent message"
        assert_selector "#ai-draft-panel [data-ai-draft-target='contextAvailability']",
          text: /at least two members/i, wait: 10
        assert_button "Suggest reply with Grok", disabled: true
        within "#ai-draft-panel" do
          click_button "Room settings"
        end
        assert_selector "#ai-room-settings [data-ai-draft-target='smartReplyStatus']",
          text: /Invite a participant and wait for acceptance/i, wait: 10
        assert_selector "#ai-room-settings [data-ai-draft-target='smartReplyToggle'][disabled]",
          visible: :all
        assert_equal 0, room.messages.count
      end
    end
  end

  test "member permission chips refresh without reload and revoke blocks contextual AI" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    room.messages.create!(user: bob, body: "What is the Rails validation error?")

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_as(alice)
      visit room_path(room)
      # Keep this permission-refresh test in user-enabled Detailed mode.
      click_button "Edit unsent message"
      within("#ai-draft-panel") { click_button "Room settings" }
      find("input[data-simple-chat-target='detailToggle']").check
      click_button "Close writing settings"
      assert_selector ".sd-ai-member-chip.is-on", text: alice.chat_label, wait: 10
      assert_selector ".sd-ai-member-chip.is-on", text: bob.chat_label, wait: 10
      click_button "Edit unsent message"
      assert_button "Suggest reply with Grok", disabled: false, wait: 10

      # Another current member revokes while Alice remains in the room.
      AiRoomContextConsent.find_by!(room: room, user: bob).revoke!
      assert_selector ".sd-ai-member-chip.is-off", text: bob.chat_label, wait: 16
      assert_selector ".sd-ai-consent-summary[data-ready='false']", wait: 10
      assert_button "Suggest reply with Grok", disabled: true
      within "#ai-draft-panel" do
        click_button "Room settings"
      end
      assert_selector "#ai-room-settings .sd-ai-member-state.is-off", text: "OFF"
      find("#ai-room-settings .sd-ai-option-disclosure--smart > summary").click
      assert_selector "#ai-room-settings .sd-ai-members-note", text: /everyone can still chat/
      assert_equal 1, room.messages.count
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
      assert_selector "#ai-draft-panel .sd-ai-task-picker:not([open])"
      find("#ai-draft-panel .sd-ai-task-picker-trigger").click
      assert_selector "#ai-draft-panel .sd-ai-task-picker[open]"
      within "#ai-draft-panel .sd-ai-task-picker-menu" do
        assert_button "Client proposal"
        click_button "Client brief"
      end
      assert_selector "#ai-draft-panel .sd-ai-task-picker:not([open])"
      assert_selector "#ai-draft-panel .sd-ai-task-picker-trigger", text: "Client brief"
      assert_equal "client_brief",
        page.evaluate_script("document.querySelector('#ai-context-task-kind').value")
      assert_button "Generate with Grok", disabled: true
      assert_selector "#ai-draft-panel .sd-ai-brief-spend-consent:not([hidden])"
      assert_unchecked_field "Authorize one paid Client Brief request", visible: :all
      # No network request is possible before explicit, single-use consent.
      check "Authorize one paid Client Brief request"
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
      assert_unchecked_field "Authorize one paid Client Brief request", visible: :all
      assert_button "Generate with Grok", disabled: true
      assert_field "Editable working copy", with: suggestion
      assert_field "chat-text", with: ""
      assert_selector "#ai-draft-panel .sd-ai-review-handoff__button",
        text: "Review document", visible: true
      assert_equal 0, room.messages.where(user: alice).count
      click_button "Apply to message"
      assert_field "chat-text", with: suggestion
      assert_equal 0, room.messages.where(user: alice).count
      end
    end
  end

  test "context reply can be refined with a second explicit Grok click without sending" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Could you clarify the task scope?")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    reply = "Could you specify the exact scope?"
    polished = "Could you please clarify the exact project scope?"

    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        click_button "Edit unsent message"
        assert_button "Suggest reply with Grok", disabled: false, wait: 10
        page.execute_script(<<~JS)
          window.__realFlowCalls = []
          window.__previousFetch = window.fetch
          window.fetch = async (url, options) => {
            if (String(url).includes("/ai/reply")) {
              window.__realFlowCalls.push("context")
              return { ok: true, json: async () => ({
                text: #{reply.to_json}, cost_usd: "0.000208",
                source_message_ids: [#{incoming.id}],
                omitted_context_messages: 0
              }) }
            }
            if (String(url).includes("/ai/draft")) {
              window.__realFlowCalls.push("draft")
              window.__secondPayload = JSON.parse(options.body)
              return { ok: true, json: async () => ({
                text: #{polished.to_json}, cost_usd: "0.000215"
              }) }
            }
            return window.__previousFetch(url, options)
          }
        JS

        click_button "Suggest reply with Grok"
        assert_field "Editable working copy", with: reply
        assert_button "Improve with Grok", disabled: false
        click_button "Improve with Grok"
        assert_field "Editable working copy", with: polished
        assert_equal reply, page.evaluate_script("window.__secondPayload.draft.text")
        assert_equal "polish_clarity",
          page.evaluate_script("window.__secondPayload.draft.preset_id")
        assert_equal "1", page.evaluate_script("window.__secondPayload.draft.consent")
        assert_equal ["context", "draft"], page.evaluate_script("window.__realFlowCalls")
        assert_field "chat-text", with: ""
        assert_equal 0, room.messages.where(user: alice).count

        click_button "Apply to message"
        assert_field "chat-text", with: polished
        assert_equal 0, room.messages.where(user: alice).count
      end
    end
  end
  test "structured preview is inert, editable, copyable and exportable without sending" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    original = room.messages.create!(user: bob, body: "Check the actual 422 validation error")
    outside = Room.create!(name: "External group", kind: "private_group",
      is_private: true, owner: bob)
    outside.participants.create!(user: bob, group_role: "owner")
    foreign = outside.messages.create!(user: bob, body: "Unrelated private data")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end
    suggestion = "# Client Brief\n- Check Rails validation [M#{original.id}]\n" \
      "- Unknown citation [M#{foreign.id}]\n<script>window.__unsafe = 1</script>"
    reviewed = suggestion + "\n- Review the database logs first"

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        click_button "Edit unsent message"
        assert_button "Generate with Grok", disabled: true
        find("#ai-draft-panel .sd-ai-task-picker-trigger").click
        within "#ai-draft-panel .sd-ai-task-picker-menu" do
          click_button "Client brief"
        end
        assert_button "Generate with Grok", disabled: true
        check "Authorize one paid Client Brief request"
        assert_button "Generate with Grok", disabled: false, wait: 10

        page.execute_script(<<~JS)
          window.__h3bCalls = 0
          window.__copyValue = null
          window.__exportFile = null
          window.__exportBlob = null
          const previousFetch = window.fetch.bind(window)
          window.fetch = async (url, options) => {
            if (String(url).includes("/ai/task")) {
              window.__h3bCalls += 1
              return { ok: true, json: async () => ({
                text: #{suggestion.to_json}, kind: "client_brief",
                source_message_ids: [#{original.id}], cost_usd: "0.000000",
                source_links: {
                  "#{original.id}": #{room_path(room, focus: original.id).to_json},
                  "#{foreign.id}": #{room_path(outside, focus: foreign.id).to_json}
                },
                omitted_context_messages: 0
              }) }
            }
            return previousFetch(url, options)
          }
          Object.defineProperty(navigator, "clipboard", {
            configurable: true, value: { writeText: async text => { window.__copyValue = text } }
          })
          const originalCreate = URL.createObjectURL.bind(URL)
          URL.createObjectURL = blob => {
            window.__exportBlob = blob
            return originalCreate(blob)
          }
          const nativeClick = HTMLAnchorElement.prototype.click
          HTMLAnchorElement.prototype.click = function() {
            if (this.download) { window.__exportFile = this.download; return }
            return nativeClick.call(this)
          }
        JS
        before = Message.count
        click_button "Generate with Grok"
        assert_selector "#ai-draft-panel .sd-ai-deliverable-preview[open]", wait: 10
        assert_selector "#ai-draft-panel .sd-ai-deliverable-preview__body h4", text: "Client Brief"
        assert_selector "#ai-draft-panel .sd-ai-deliverable-preview__body li", count: 2
        assert_selector "#ai-draft-panel .sd-ai-preview-citation[href*='focus=#{original.id}']"
        assert_no_selector "#ai-draft-panel .sd-ai-preview-citation[href*='focus=#{foreign.id}']"
        assert_no_selector "#ai-draft-panel .sd-ai-deliverable-preview script, #ai-draft-panel .sd-ai-deliverable-preview img", visible: :all
        assert_nil page.evaluate_script("window.__unsafe")
        assert_selector "#ai-draft-panel .sd-ai-deliverable-preview", text: "<script>window.__unsafe = 1</script>"
        assert_field "chat-text", with: ""
        assert_equal 1, page.evaluate_script("window.__h3bCalls")
        assert_equal before, Message.count

        fill_in "Editable working copy", with: reviewed
        assert_selector "#ai-draft-panel .sd-ai-deliverable-preview", text: "Review the database logs first"
        click_button "Copy"
        assert_selector "#ai-draft-panel [data-ai-draft-target='previewFeedback']", text: /Copied reviewed Markdown/
        assert_equal reviewed, page.evaluate_script("window.__copyValue")
        click_button "Export .md"
        assert_selector "#ai-draft-panel [data-ai-draft-target='previewFeedback']", text: /Local Markdown export started/
        assert_equal "client-brief.md", page.evaluate_script("window.__exportFile")
        exported = page.evaluate_async_script(<<~JS)
          const done = arguments[0]
          window.__exportBlob.text().then(done)
        JS
        assert_equal reviewed, exported
        assert_equal before, Message.count
        assert_equal 1, page.evaluate_script("window.__h3bCalls")

        AiRoomContextConsent.find_by!(room: room, user: bob).revoke!
        assert_button "Copy", disabled: true, wait: 16
        assert_button "Export .md", disabled: true
        assert_field "Editable working copy", with: reviewed
        assert_equal before, Message.count
      end
    end
  end

  test "named local author template is scoped, editable, inert and used only on explicit context task" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Please clarify the scope of work.")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    instruction = "Summarize the agreed scope. Mark missing dates To confirm."
    updated = "List acceptance criteria. Mark missing dates To confirm."

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        key = "turbo-chat:ai-instructions:v1:user:#{alice.id}:room:#{room.id}"
        page.execute_script("localStorage.removeItem(arguments[0])", key)
        visit room_path(room)
        click_button "Edit unsent message"
        assert_button "Generate with Grok", disabled: true
        find("#ai-draft-panel .sd-ai-custom-instructions > summary").click
        fill_in "Custom instruction for contextual AI", with: instruction
        fill_in "Template name", with: "Scope review"
        before = Message.count
        click_button "Save template"
        assert_selector "#ai-draft-panel .sd-ai-custom-instructions__feedback", text: /Saved on this device/
        assert_selector "#ai-draft-panel .sd-ai-local-template", text: "Scope review"
        assert_equal before, Message.count
        assert_field "chat-text", with: ""

        # A local template does not store the working draft or the room's messages.
        data = page.evaluate_script("localStorage.getItem(arguments[0])", key)
        assert_includes data, instruction
        assert_not_includes data, incoming.body
        assert_not_includes data, incoming.id.to_s + "]"

        fill_in "Custom instruction for contextual AI", with: updated
        click_button "Save template"
        assert_selector "#ai-draft-panel .sd-ai-local-template", count: 1
        visit room_path(room)
        click_button "Edit unsent message"
        find("#ai-draft-panel .sd-ai-custom-instructions > summary").click
        assert_selector "#ai-draft-panel .sd-ai-local-template", text: "Scope review"
        assert_selector "#ai-draft-panel .sd-ai-local-template button[aria-label='Use template Scope review']"
        find("#ai-draft-panel .sd-ai-local-template button[aria-label='Use template Scope review']").click
        assert_field "Custom instruction for contextual AI", with: updated

        # Save/Use/reload are all local; only Generate requests xAI.
        page.execute_script(<<~JS)
          window.__customTaskCalls = 0
          const oldFetch = window.fetch
          window.fetch = async (url, options) => {
            if (String(url).includes("/ai/task")) {
              window.__customTaskCalls += 1
              window.__customTaskPayload = JSON.parse(options.body)
              return { ok: true, json: async () => ({
                text: "Check scope [M#{incoming.id}]", kind: "client_brief",
                source_message_ids: [#{incoming.id}], source_links: {
                  "#{incoming.id}": #{room_path(room, focus: incoming.id).to_json}
                }, cost_usd: "0.000000", omitted_context_messages: 0
              }) }
            }
            return oldFetch(url, options)
          }
        JS
        assert_equal 0, page.evaluate_script("window.__customTaskCalls")
        find("#ai-draft-panel .sd-ai-task-picker-trigger").click
        within "#ai-draft-panel .sd-ai-task-picker-menu" do
          click_button "Client brief"
        end
        assert_button "Generate with Grok", disabled: true
        check "Authorize one paid Client Brief request"
        assert_button "Generate with Grok", disabled: false, wait: 10
        click_button "Generate with Grok"
        assert_field "Editable working copy", with: "Check scope [M#{incoming.id}]"
        assert_equal updated, page.evaluate_script("window.__customTaskPayload.task.hint")
        assert_equal "1", page.evaluate_script("window.__customTaskPayload.task.consent")
        assert_equal 1, page.evaluate_script("window.__customTaskCalls")
        assert_equal before, Message.count
        assert_field "chat-text", with: ""
      end
    end
  end

  test "template names are rendered as text, dangerous notes rejected and room scope isolated" do
    alice, bob = users(:one), users(:two)
    first = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    second = Room.create!(name: "Separate private workspace", kind: "private_group",
      is_private: true, owner: alice)
    second.participants.create!(user: alice, group_role: "owner")
    second.participants.create!(user: bob, group_role: "member")
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_as(alice)
      visit room_path(first)
      [first, second].each do |target|
        key = "turbo-chat:ai-instructions:v1:user:#{alice.id}:room:#{target.id}"
        page.execute_script("localStorage.removeItem(arguments[0])", key)
      end
      visit room_path(first)
      click_button "Edit unsent message"
      find("#ai-draft-panel .sd-ai-custom-instructions > summary").click
      fill_in "Custom instruction for contextual AI", with: "Send my email to client@example.com"
      fill_in "Template name", with: "Invalid"
      click_button "Save template"
      assert_selector "#ai-draft-panel .sd-ai-custom-instructions__feedback", text: /without emails, tokens/
      assert_no_selector "#ai-draft-panel .sd-ai-local-template"

      fill_in "Custom instruction for contextual AI", with: "Write a concise review of confirmed requirements."
      fill_in "Template name", with: '<img src=x onerror="window.__unsafeTemplate=1">'
      click_button "Save template"
      assert_selector "#ai-draft-panel .sd-ai-local-template", text: /img src=x/
      assert_no_selector "#ai-draft-panel .sd-ai-custom-instructions img", visible: :all
      assert_nil page.evaluate_script("window.__unsafeTemplate")
      visit room_path(second)
      click_button "Edit unsent message"
      find("#ai-draft-panel .sd-ai-custom-instructions > summary").click
      assert_no_selector "#ai-draft-panel .sd-ai-local-template"
      visit room_path(first)
      click_button "Edit unsent message"
      find("#ai-draft-panel .sd-ai-custom-instructions > summary").click
      assert_selector "#ai-draft-panel .sd-ai-local-template", count: 1
      accept_confirm do
        find("#ai-draft-panel .sd-ai-local-template__delete").click
      end
      assert_no_selector "#ai-draft-panel .sd-ai-local-template"
    end
  end

  test "manual local source review explains in-room citations without a paid request" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Please review Rails validations for the proposal.")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      login_as(alice)
      visit room_path(room)
      click_button "Edit unsent message"
      assert_selector "#ai-draft-panel .sd-ai-source-review", visible: :all
      find("#ai-draft-panel .sd-ai-source-review > summary").click
      assert_button "Review sources", disabled: false, wait: 10
      before = Message.count
      click_button "Review sources"
      assert_selector "#ai-draft-panel .sd-ai-source-review__list li", minimum: 1, wait: 10
      assert_selector "#ai-draft-panel .sd-ai-source-review__list", text: "Rails validations"
      assert_selector "#ai-draft-panel .sd-ai-source-review__list a[href*='focus=#{incoming.id}']"
      assert_selector "#ai-draft-panel .sd-ai-source-review__contents", text: "Only checked excerpts"
      assert_field "chat-text", with: ""
      assert_equal before, Message.count

      # Consent polling invalidates previously disclosed preview after revocation.
      AiRoomContextConsent.find_by!(room: room, user: bob).revoke!
      assert_button "Review sources", disabled: true, wait: 15
      assert_no_selector "#ai-draft-panel .sd-ai-source-review__list li", visible: :all
      assert_equal before, Message.count
    end
  end

  test "context source checkboxes only send explicitly included IDs on manual task click" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    noise = room.messages.create!(user: bob, body: "hey")
    room.messages.create!(user: bob, body: "Upcoming meeting planning.")
    room.messages.create!(user: bob, body: "Proposal API requirements.")
    incoming = room.messages.create!(user: bob, body: "Please review Rails API validations.")
    [alice, bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    end
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        login_as(alice)
        visit room_path(room)
        click_button "Edit unsent message"
        find("#ai-draft-panel .sd-ai-source-review > summary").click
        assert_button "Review sources", disabled: false, wait: 10
        before = Message.count
        click_button "Review sources"
        assert_selector "#ai-draft-panel .sd-ai-source-review__list input[type=checkbox]", minimum: 4, wait: 10
        noise_check = find("#ai-draft-panel .sd-ai-source-review__list input[data-source-id='#{noise.id}']")
        assert_not noise_check.checked?, "Old irrelevant fallback should default unchecked"
        incoming_check = find("#ai-draft-panel .sd-ai-source-review__list input[data-source-id='#{incoming.id}']")
        assert incoming_check.checked?

        # The owner's choice is reversible and no provider call happens during review.
        find("#ai-draft-panel .sd-ai-source-review__list input[data-source-id='#{incoming.id}']").set(false)
        find("#ai-draft-panel .sd-ai-source-review__list input[data-source-id='#{incoming.id}']").set(true)
        checked = page.evaluate_script(<<~JS)
          Array.from(document.querySelectorAll("#ai-draft-panel .sd-ai-source-review__list input:checked"))
            .map(el => Number(el.dataset.sourceId))
        JS
        assert_not_includes checked, noise.id
        assert_includes checked, incoming.id
        assert_equal before, Message.count

        page.execute_script(<<~JS)
          window.__selectedTaskCalls = 0
          const originalFetch = window.fetch.bind(window)
          window.fetch = async (url, options) => {
            if (String(url).includes("/ai/task")) {
              window.__selectedTaskCalls += 1
              window.__selectedTaskPayload = JSON.parse(options.body)
              return { ok: true, json: async () => ({
                text: "Review Rails validations [M#{incoming.id}]",
                kind: "client_brief",
                source_message_ids: [#{incoming.id}],
                source_links: { "#{incoming.id}": #{room_path(room, focus: incoming.id).to_json} },
                cost_usd: "0.000000", omitted_context_messages: 0,
                evidence_review: {
                  version: 1, assessment: "structural_only_not_fact_checked",
                  checked_lines: 2, linked_lines: 1, uncited_lines: 1,
                  weak_overlap_lines: 0, needs_confirmation_lines: 1,
                  cited_source_ids: [#{incoming.id}], truncated: false,
                  issues: [{ line: 2, signal: "needs_confirmation" }]
                }
              }) }
            }
            return originalFetch(url, options)
          }
        JS
        find("#ai-draft-panel .sd-ai-task-picker-trigger").click
        within "#ai-draft-panel .sd-ai-task-picker-menu" do
          click_button "Client brief"
        end
        assert_button "Generate with Grok", disabled: true
        check "Authorize one paid Client Brief request"
        assert_button "Generate with Grok", disabled: false, wait: 10
        assert_equal 0, page.evaluate_script("window.__selectedTaskCalls")
        click_button "Generate with Grok"
        assert_field "Editable working copy", with: "Review Rails validations [M#{incoming.id}]"
        assert_selector "#ai-draft-panel .sd-ai-evidence-review summary",
          text: /Evidence review.*1 linked/, visible: :all
        assert_selector "#ai-draft-panel .sd-ai-evidence-review li",
          text: /Line 2: Not yet confirmed/, visible: :all
        payload = page.evaluate_script("window.__selectedTaskPayload.task")
        assert_kind_of String, payload.fetch("source_token")
        assert_operator payload.fetch("source_token").length, :>, 100
        assert_equal checked, payload.fetch("source_ids")
        assert_equal "1", payload.fetch("consent")
        assert_equal 1, page.evaluate_script("window.__selectedTaskCalls")
        assert_field "chat-text", with: ""
        assert_equal before, Message.count
      end
    end
  end

end
