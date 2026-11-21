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

  test "missing purpose shows a compact blocker and opens instructions only on explicit action" do
    open_room
    assert_selector ".sd-ai-answer-status", visible: :all,
      text: "save room instructions", wait: 10
    find(".composer-controls .sd-ai-answer-entry").click
    assert_selector ".sd-ai-answer-readiness[data-state='goal']:not([hidden])",
      text: "save room instructions", wait: 10
    assert_no_selector "#ai-room-settings[open]"
    click_button "Set room purpose"
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
      text: "Live AI generation is not enabled", wait: 10
    find(".composer-controls .sd-ai-answer-entry").click
    assert_selector ".sd-ai-answer-readiness[data-state='provider']:not([hidden])",
      text: "Live AI generation is not enabled", wait: 10
    assert_no_selector ".sd-ai-answer-result:not([hidden])"
    click_button "Preview context without AI"
    assert_selector ".sd-ai-answer-result:not([hidden])",
      text: "Can we confirm the Rails signup acceptance criteria?", wait: 10
    assert_selector ".sd-ai-answer-result", text: "Clarify scope before agreeing to work"
    # Preview has no editable AI composer and no Send affordance.
    assert_no_selector ".sd-ai-answer-composer:not([hidden])", visible: :all
    assert_equal 1, @room.messages.count
    assert_field "chat-text", with: ""
  end

  test "one shared inspector previews Answer and Beautify without model requests or Send" do
    save_instruction
    grant_all
    open_room
    assert_button "AI plan"

    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan:not([hidden])", wait: 10
    assert_selector ".sd-ai-effective-plan__status",
      text: "Prepared locally", wait: 10
    assert_selector ".sd-ai-effective-plan__body",
      text: "suggest_reply_for_human_review"
    assert_selector ".sd-ai-effective-plan__body",
      text: "Can we confirm the Rails signup acceptance criteria?"
    assert_selector ".sd-ai-effective-plan__body",
      text: "NOT full room history"
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count

    fill_in "chat-text", with: "Please fix Rails copy."
    assert_selector ".sd-ai-effective-plan[hidden]", visible: :all
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan__status",
      text: "Prepared locally", wait: 10
    assert_selector ".sd-ai-effective-plan__body",
      text: "beautify_own_unsent_draft"
    assert_selector ".sd-ai-effective-plan__body",
      text: "Please fix Rails copy."
    assert_selector ".sd-ai-effective-plan__body",
      text: "no peer messages are included"
    assert_no_selector ".sd-ai-answer-result[data-mode='candidate']:not([hidden])"
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
    assert_field "chat-text", with: "Please fix Rails copy."
  end

  test "AI plan is dismissible by toggle, close button, Escape and outside pointer" do
    save_instruction
    grant_all
    open_room
    trigger = ".sd-ai-plan-inspect-button"
    assert_selector "#{trigger}[aria-expanded='false']"

    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan__status", text: "Prepared locally", wait: 10
    assert_selector "#{trigger}[aria-expanded='true']"
    assert_selector ".sd-ai-plan-grid .sd-ai-plan-card", minimum: 5
    assert_selector ".sd-ai-plan-source--target[open]"
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan[hidden]", visible: :all
    assert_selector "#{trigger}[aria-expanded='false']"

    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan:not([hidden])", wait: 10
    assert_selector ".sd-ai-effective-plan[data-motion='open']", wait: 10
    before = page.evaluate_script(
      "document.querySelector('.sd-ai-effective-plan').getBoundingClientRect().height")
    find(".sd-ai-effective-plan__grip").send_keys(:arrow_up)
    after = page.evaluate_script(
      "document.querySelector('.sd-ai-effective-plan').getBoundingClientRect().height")
    assert_operator after, :>, before

    find(".sd-ai-effective-plan__close").click
    assert_selector ".sd-ai-effective-plan[hidden][data-motion='closed']",
      visible: :all, wait: 10
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan:not([hidden])", wait: 10
    find(".sd-ai-effective-plan__close").send_keys(:escape)
    assert_selector ".sd-ai-effective-plan[hidden]", visible: :all

    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan:not([hidden])", wait: 10
    find("#messages-container").click
    assert_selector ".sd-ai-effective-plan[hidden]", visible: :all
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
    assert_field "chat-text", with: ""
  end

  test "rapid AI plan toggles reverse animations without spending or losing the human draft" do
    save_instruction
    grant_all
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan__status", text: "Prepared locally", wait: 10

    # A pair of same-frame clicks must end closed; an old animation cannot
    # hide a subsequently reopened panel.
    page.execute_script(<<~JS)
      const button = document.querySelector(".sd-ai-plan-inspect-button")
      button.click()
      button.click()
    JS
    assert_selector ".sd-ai-plan-inspect-button[aria-expanded='true']", wait: 10
    assert_selector ".sd-ai-effective-plan[data-motion='open']", wait: 10
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan[hidden][data-motion='closed']",
      visible: :all, wait: 10
    assert_field "chat-text", with: ""
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
  end

  test "AI plan safely formats Markdown instructions without raw markers or executable HTML" do
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1,
      content: "**Rules:**\n1. Clarify work scope\n2. Confirm requirements")
    grant_all
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-effective-plan__status", text: "Prepared locally", wait: 10
    within ".sd-ai-effective-plan__body" do
      assert_selector ".sd-ai-plan-markdown__heading", text: "Rules:"
      assert_selector ".sd-ai-plan-markdown__marker", text: "1."
      assert_selector ".sd-ai-plan-markdown__marker", text: "2."
      assert_no_text "**Rules:**"
      assert_no_selector "script"
      assert_selector ".sd-ai-plan-card--amber"
      assert_selector ".sd-ai-plan-card--green"
    end
    assert_equal 0, AiUsageReservation.count
  end

  test "AI plan saves writing preference through shared room model and recompiles without AI" do
    save_instruction
    grant_all
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-plan-preferences select[data-plan-field='profile_id']", visible: :all, wait: 10
    within ".sd-ai-plan-preferences" do
      assert_selector ".sd-ui-select__trigger", minimum: 4, wait: 10
      find(".sd-ai-plan-edit__label:has(select[data-plan-field='profile_id']) .sd-ui-select__trigger").click
      find(".sd-ui-select__menu[role='listbox'] .sd-ui-select__option",
        text: "Business", exact_text: true).click
      page.execute_script(<<~JS)
        const language = document.querySelector(
          '.sd-ai-plan-preferences select[data-plan-field="language"]')
        language.value = 'ru'
        language.dispatchEvent(new Event('change', {bubbles:true}))
        language.dispatchEvent(new Event('ui-select:sync'))
      JS
      click_button "Save preferences"
    end
    assert_selector ".sd-ai-effective-plan__status",
      text: "Prepared locally", wait: 10
    assert_selector ".sd-ai-plan-preferences select[data-plan-field='profile_id']" +
      " option[value='business']:checked", visible: :all, wait: 10
    assert_selector ".sd-ai-plan-edit__feedback[data-state='saved']",
      text: "Saved and synchronized", wait: 10
    assert_equal "business", AiRoomWritingPreference.find_by!(room: @room, user: @alice).profile_id
    assert_equal "professional_client_reply",
      AiRoomWritingPreference.find_by!(room: @room, user: @alice).writing_style
    assert_equal "ru", AiRoomWritingPreference.find_by!(room: @room, user: @alice).language
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
    click_button "AI plan"
    click_button "Edit unsent message"
    click_button "Room settings"
    assert_selector ".sd-ai-experience-profiles__choice[data-profile-id='business'][aria-pressed='true']"
  end

  test "AI plan edits room instructions using the canonical append-only revision controller" do
    save_instruction
    grant_all
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-plan-goal-editor", wait: 10
    within ".sd-ai-plan-goal-editor" do
      find("summary").click
      find("textarea").fill_in with: "Reply to the latest incoming Rails request, without inventing a price."
      click_button "Save new version"
    end
    assert_selector ".sd-ai-effective-plan__status",
      text: "Prepared locally", wait: 10
    assert_equal 2, @room.ai_instruction_revisions.count
    assert_equal "Reply to the latest incoming Rails request, without inventing a price.",
      @room.ai_instruction_revisions.order(:revision_number).last.content
    assert_selector ".sd-ai-plan-edit__feedback[data-state='saved']",
      text: "New instruction revision saved", wait: 10
    assert_selector ".sd-ai-plan-card", text: "Instruction revision"
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
  end

  test "AI plan selects an older incoming message and reduces sources without a provider call" do
    save_instruction
    grant_all
    older = @room.messages.first
    newer = @room.messages.create!(user: @bob,
      body: "Please send the updated homepage layout.")
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-plan-source-editor input[data-source-id='#{older.id}']", wait: 10
    assert_selector ".sd-ai-plan-source-editor select[data-plan-field='reply_target_id']", visible: :all
    within ".sd-ai-plan-source-editor" do
      assert_selector ".sd-ui-select__trigger", minimum: 1, wait: 10
      # Unchecking the current (latest) target automatically promotes the
      # newest still-included incoming turn; no confusing manual repair.
      find("input[data-source-id='#{newer.id}']").uncheck
      assert_selector "select[data-plan-field='reply_target_id']" +
        " option[value='#{older.id}']:checked", visible: :all, wait: 10
      click_button "Apply to AI Answer"
    end
    assert_selector ".sd-ai-plan-edit__feedback[data-state='saved']",
      text: "Applied:", wait: 10
    assert_selector ".sd-ai-plan-source--target", text: "M#{older.id}", wait: 10
    assert_no_selector ".sd-ai-plan-source summary", text: "M#{newer.id}"
    assert_selector ".sd-ai-plan-card--amber", text: "M#{older.id}"
    assert_equal 0, AiUsageReservation.count
    assert_equal 2, @room.messages.count
  end

  test "AI plan disables Apply if all incoming messages are unchecked and recovers without cost" do
    save_instruction
    grant_all
    older = @room.messages.first
    own = @room.messages.create!(user: @alice, body: "We need a clear scope.")
    open_room
    click_button "AI plan"
    assert_selector ".sd-ai-plan-source-editor input[data-source-id='#{older.id}']", wait: 10
    within ".sd-ai-plan-source-editor" do
      find("input[data-source-id='#{older.id}']").uncheck
      assert_button "Apply to AI Answer", disabled: true
      assert_selector ".sd-ai-plan-edit__feedback[data-state='error']",
        text: "Choose at least one incoming message"
      # Outgoing messages remain available as context but cannot be targets.
      assert find("input[data-source-id='#{own.id}']").checked?
      find("input[data-source-id='#{older.id}']").check
      assert_button "Apply to AI Answer", disabled: false
      click_button "Apply to AI Answer"
    end
    assert_selector ".sd-ai-plan-edit__feedback[data-state='saved']", text: "Applied:", wait: 10
    assert_equal 0, AiUsageReservation.count
    assert_equal 2, @room.messages.count
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
      assert_selector ".sd-ai-answer-readiness[data-state='consent']:not([hidden])",
        text: "grants", wait: 10
      assert_no_selector "#ai-room-settings[open]"
      click_button "Manage room consent"
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
    assert_selector ".sd-ai-answer-readiness[data-state='goal']:not([hidden])", wait: 10
    click_button "Set room purpose"
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
      # The count can be satisfied by existing local templates before the
      # asynchronous room history is reconciled. Wait for the exact saved
      # version and verify its text rather than scanning an early snapshot.
      version_label = find(".sd-room-ai-instructions__history-entry summary small",
        text: /\AVersion 1\z/, wait: 10)
      entry = version_label.find(:xpath, "../..")
      assert_equal "Clarify the first scope.",
        entry.find("pre", visible: :all).text(:all).strip
      entry.find("summary").click
      entry.click_button "Apply to room now"
      assert_selector ".sd-room-ai-instructions__revision", text: "Version 3", wait: 10
    end
    assert_equal "Clarify the first scope.",
      RoomAiInstructionRevision.where(room: @room).order(:revision_number).last.content
    assert_equal 1, @room.messages.count
  end



  test "paid answer requires confirmation and review before a separate signed Send" do
    save_instruction
    grant_all
    fake = Object.new
    # A fake result exercises the full browser submission without network/fees.
    source_id = @room.messages.first.id
    fake.define_singleton_method(:call) do |**opts|
      request = AiWorkspace::GenerationOrchestrator::Request.new(
        mode: "answer", actor: opts.fetch(:actor), room: opts.fetch(:room),
        draft_text: "", request_id: opts.fetch(:request_id),
        expected_goal_revision: 1, confirmed: "1",
        goal_source: "room_instructions")
      plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: request)
      input = AiWorkspace::GenerationInputContract.build!(plan: plan, request: request)
      AiWorkspace::AnswerGeneration::Result.new(
        text: "Please share the Rails validation log and expected form behavior.",
        model: "grok-4.3", cost_ticks: 20_000_000,
        source_ids: [source_id], goal_revision: 1,
        request_id: request.request_id, fingerprint: input.fingerprint)
    end

    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:new, -> { fake }) do
        open_room
        assert_selector ".sd-ai-answer-status", text: "ready for a one-shot generation", visible: :all
        before = @room.messages.count
        accept_confirm do
          find(".composer-controls .sd-ai-answer-entry").click
        end
        assert_field "AI draft (editable before sending)",
          with: "Please share the Rails validation log and expected form behavior.", wait: 10
        assert_selector ".sd-ai-answer-result[data-mode='candidate'][data-cost-usd='0.002000']"
        assert_no_selector ".sd-ai-answer-result[data-mode='candidate'] pre", visible: true
        assert_selector ".sd-ai-answer-composer:not([hidden]) .sd-ai-answer-send", visible: true
        assert_selector ".sd-ai-answer-composer:not([hidden]) .sd-ai-answer-candidate", visible: true
        assert_field "chat-text", with: ""
        assert_equal before, @room.messages.count
        fill_in "AI draft (editable before sending)",
          with: "Please share the Rails validation error and a reproducible example."
        click_button "Send this AI version"
        assert_selector ".sd-message",
          text: "Please share the Rails validation error and a reproducible example.", wait: 10
        assert_equal before + 1, @room.messages.count
        assert_equal true, @room.messages.order(:id).last.ai_assisted?
      end
    end
  end


  test "synthetic no-cost Answer requires explicit Send and stays labelled as a test" do
    save_instruction
    grant_all

    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        open_room
        assert_selector ".sd-ai-answer-status", text: "SYNTHETIC demo", visible: :all, wait: 10
        before = @room.messages.count
        accept_confirm do
          find(".composer-controls .sd-ai-answer-entry").click
        end
        assert_field "Test draft (not an AI model answer; editable)",
          with: /СИНТЕТИЧЕСКИЙ ТЕСТ/, wait: 10
        assert_selector ".sd-ai-answer-result[data-mode='candidate'][data-cost-usd='0.000000']", wait: 10
        assert_no_selector ".sd-ai-answer-result[data-mode='candidate'] pre", visible: true
        assert_no_selector ".sd-ai-answer-result[data-mode='candidate'] .sd-ai-answer-result-head", visible: true
        assert find(".sd-ai-answer-regenerate", visible: :all).disabled?
        assert_equal "Regenerate AI answer",
          find(".sd-ai-answer-regenerate", visible: :all)["aria-label"]
        assert_selector ".sd-ai-answer-result[data-mode='candidate'] .sd-ai-answer-composer:not([hidden])", wait: 10
        # Pixel-accurate twin: fields, two paper planes and top-edge resize
        # handles share X coordinates. The AI toolbar is confined LEFT of text.
        assert_selector ".sd-ai-answer-grip", visible: true
        layout = page.evaluate_script(<<~JS)
          (() => {
            const rect = selector => document.querySelector(selector).getBoundingClientRect()
            const ai = rect(".sd-ai-answer-candidate")
            const human = rect(".composer-controls #chat-text")
            const plane = rect(".sd-ai-answer-composer .sd-ai-answer-send")
            const native = rect(".composer-controls .composer-send")
            const aiGrip = rect(".sd-ai-answer-grip")
            const humanGrip = rect(".composer-controls .sd-quick-beautify-grip")
            return {aiLeft:ai.left, humanLeft:human.left,
              aiRight:ai.right, humanRight:human.right,
              planeLeft:plane.left, nativeLeft:native.left,
              planeRight:plane.right, nativeRight:native.right,
              aiGripCenter:aiGrip.left + aiGrip.width/2,
              humanGripCenter:humanGrip.left + humanGrip.width/2,
              planeHeight:plane.height, nativeHeight:native.height}
          })()
        JS
        assert_in_delta layout.fetch("humanLeft"), layout.fetch("aiLeft"), 1.0
        assert_in_delta layout.fetch("humanRight"), layout.fetch("aiRight"), 1.0
        assert_in_delta layout.fetch("nativeLeft"), layout.fetch("planeLeft"), 1.0
        assert_in_delta layout.fetch("nativeRight"), layout.fetch("planeRight"), 1.0
        # Chrome fractional layout occasionally differs by 1.00006px at device scale.
        assert_in_delta layout.fetch("nativeHeight"), layout.fetch("planeHeight"), 1.25
        assert_in_delta layout.fetch("humanGripCenter"), layout.fetch("aiGripCenter"), 1.0
        initial = page.evaluate_script(
          "document.querySelector('.sd-ai-answer-candidate').getBoundingClientRect().height")
        find(".sd-ai-answer-grip").send_keys(:arrow_up)
        assert_operator page.evaluate_script(
          "document.querySelector('.sd-ai-answer-candidate').getBoundingClientRect().height"), :>, initial
        assert_equal before, @room.messages.count
        assert_equal 0, AiUsageReservation.count
        assert_field "chat-text", with: ""
        # Both editors remain independent until the user selects an airplane.
        fill_in "chat-text", with: "Human alternative, do not send."
        assert_field "Test draft (not an AI model answer; editable)",
          with: /СИНТЕТИЧЕСКИЙ ТЕСТ/
        assert_field "chat-text", with: "Human alternative, do not send."
        assert_selector ".sd-ai-answer-composer .sd-ai-answer-send", visible: true
        click_button "Send test answer"
        assert_selector ".sd-message", text: "СИНТЕТИЧЕСКИЙ ТЕСТ", wait: 10
        assert_equal before + 1, @room.messages.count
        assert_equal true, @room.messages.order(:id).last.ai_assisted?
        assert_equal 0, AiUsageReservation.count
      end
    end
  end

  test "new AI regeneration is locked until settings are explicitly saved" do
    save_instruction
    grant_all
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        open_room
        accept_confirm { find(".composer-controls .sd-ai-answer-entry").click }
        assert_selector ".sd-ai-answer-result[data-mode='candidate']", wait: 10
        assert_selector ".sd-ai-answer-candidate-head:not([hidden])"
        assert_selector ".sd-ai-answer-cost:not([hidden])", text: "$0.000000"
        assert_selector ".sd-ai-answer-entry .sd-ai-answer-readiness-indicator svg", visible: true
        assert find(".sd-ai-answer-regenerate", visible: :all).disabled?
        assert_button "Send test answer", disabled: false

        # This event is emitted ONLY upon successful PATCH of writing settings.
        page.execute_script(<<~JS)
          document.querySelector(".msg-form").dispatchEvent(
            new CustomEvent("ai-draft:preferences-saved", {bubbles:true}))
        JS
        assert_not find(".sd-ai-answer-regenerate", visible: :all).disabled?
        assert_button "Send test answer", disabled: true
        assert_equal 0, AiUsageReservation.count
        accept_confirm { find(".sd-ai-answer-regenerate", visible: :all).click }
        assert_selector ".sd-ai-answer-result[data-mode='candidate']", wait: 10
        assert find(".sd-ai-answer-regenerate", visible: :all).disabled?
        assert_button "Send test answer", disabled: false
        assert_equal 1, @room.messages.count
        assert_equal 0, AiUsageReservation.count
      end
    end
  end

end
