require "application_system_test_case"
require "minitest/mock"

class AiManualSuggestionResultSystemTest < ApplicationSystemTestCase
  def login_as_owner(user)
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

  test "identical Grok suggestion is clearly reported as no edit and original draft remains untouched" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    original = "I has received document and will answer tomorow."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      login_as_owner(alice)
      visit room_path(room)
      fill_in "chat-text", with: original
      click_button "Edit unsent message"
      assert_selector "#ai-draft-panel:not([hidden]) .sd-ai-manual-generate"
      page.execute_script(<<~JS)
        window.__grokFakeCalls = 0
        window.fetch = async (_url, options) => {
          window.__grokFakeCalls += 1
          window.__grokFakePayload = JSON.parse(options.body)
          return { ok: true, json: async () => ({
            text: #{original.to_json}, cost_usd: "0.000208"
          }) }
        }
      JS
      assert_no_selector "#ai-draft-panel input[type=checkbox]"
      assert_selector "#ai-draft-panel .sd-ai-consent-note", text: /Only this unsent draft goes to xAI/
      click_button "Improve with Grok"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /No changes/
      assert_selector "#ai-draft-panel .sd-ai-provider-details", text: /0\.000208/, visible: :all
      assert_no_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /0\.000208/
      assert_field "Editable working copy", with: original
      assert_field "chat-text", with: original
      assert_button "Apply to message", disabled: true
      assert_equal 1, page.evaluate_script("window.__grokFakeCalls")
      assert_equal original, page.evaluate_script("window.__grokFakePayload.draft.text")
      assert_equal "1", page.evaluate_script("window.__grokFakePayload.draft.consent")
      assert_equal 0, room.messages.count
    end
  end

  test "changed Grok suggestion needs explicit Apply and never automatically sends" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    original = "I has received document and will answer tomorow."
    revised = "I have received the document and will answer tomorrow."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      login_as_owner(alice)
      visit room_path(room)
      fill_in "chat-text", with: original
      click_button "Edit unsent message"
      page.execute_script(<<~JS)
        window.__grokFakeCalls = 0
        window.fetch = async () => {
          window.__grokFakeCalls += 1
          return { ok: true, json: async () => ({
            text: #{revised.to_json}, cost_usd: "0.000208"
          }) }
        }
      JS
      assert_no_selector "#ai-draft-panel input[type=checkbox]"
      assert_selector "#ai-draft-panel .sd-ai-consent-note", text: /Only this unsent draft goes to xAI/
      click_button "Improve with Grok"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /Suggested edit/
      assert_selector "#ai-draft-panel .sd-ai-compare-original", text: original
      assert_field "Editable working copy", with: revised
      assert_field "chat-text", with: original
      assert_button "Apply to message", disabled: false
      assert_equal 0, room.messages.count

      click_button "Apply to message"
      assert_selector "#ai-draft-panel[hidden]", visible: :all
      assert_field "chat-text", with: revised
      assert_equal 0, room.messages.count
      assert_selector ".sd-ai-quick-undo:not([hidden])", visible: true
      assert_button "Undo applied AI edit"
      click_button "Undo applied AI edit"
      assert_field "chat-text", with: original
      assert_equal 0, room.messages.count
      assert_equal 1, page.evaluate_script("window.__grokFakeCalls")
    end
  end

  test "translation sends only explicit preset and target then requires Apply and ordinary Send" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    input = "Safe synthetic text for a translation."
    translated = "Тестовый перевод."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      login_as_owner(alice)
      visit room_path(room)
      fill_in "chat-text", with: input
      click_button "Edit unsent message"
      find("#ai-draft-panel summary.sd-ai-style-summary").click
      within "#ai-draft-panel .sd-ai-draft-presets" do
        click_button "Translate Preserving Tone"
      end
      assert_selector "#ai-draft-panel .sd-ai-translation-controls:not([hidden])"
      assert_button "Translate with Grok", disabled: true
      assert_equal false, page.evaluate_script("document.querySelector('#ai-draft-target-locale').disabled")
      select "Русский", from: "ai-draft-target-locale"
      assert_button "Translate with Grok", disabled: false
      page.execute_script(<<~JS)
        window.__h3f3Calls = 0
        window.fetch = async (_url, options) => {
          window.__h3f3Calls += 1
          window.__h3f3Payload = JSON.parse(options.body)
          return { ok: true, json: async () => ({
            text: #{translated.to_json}, cost_usd: "0.000208"
          }) }
        }
      JS
      click_button "Translate with Grok"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /Suggested edit/
      assert_equal "translate_preserving_tone",
        page.evaluate_script("window.__h3f3Payload.draft.preset_id")
      assert_equal "ru", page.evaluate_script("window.__h3f3Payload.draft.target_locale")
      assert_equal "1", page.evaluate_script("window.__h3f3Payload.draft.consent")
      assert_equal input, page.evaluate_script("window.__h3f3Payload.draft.text")
      assert_equal 1, page.evaluate_script("window.__h3f3Calls")
      assert_field "chat-text", with: input
      assert_field "Editable working copy", with: translated
      assert_equal 0, room.messages.count
      click_button "Apply to message"
      assert_field "chat-text", with: translated
      assert_equal 0, room.messages.count
      click_button "Undo applied AI edit"
      assert_field "chat-text", with: input
      assert_equal 0, room.messages.count
    end
  end
end
