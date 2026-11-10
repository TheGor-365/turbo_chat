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
      assert_selector ".sd-ai-manual-generate"
      fill_in "chat-text", with: original
      click_button "Edit unsent message"
      within "#ai-draft-panel" do
        find("button[data-preset-id='polish_clarity']").click
      end
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
      check "I agree to send this draft to xAI for this one request."
      click_button "Generate suggestion"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /returned the draft unchanged/
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /0\.000208/
      assert_field "Editable working copy", with: original
      assert_field "chat-text", with: original
      assert_button "Apply to message", disabled: true
      assert_unchecked_field "I agree to send this draft to xAI for this one request."
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
      within "#ai-draft-panel" do
        find("button[data-preset-id='polish_clarity']").click
      end
      page.execute_script(<<~JS)
        window.__grokFakeCalls = 0
        window.fetch = async () => {
          window.__grokFakeCalls += 1
          return { ok: true, json: async () => ({
            text: #{revised.to_json}, cost_usd: "0.000208"
          }) }
        }
      JS
      check "I agree to send this draft to xAI for this one request."
      click_button "Generate suggestion"
      assert_selector "#ai-draft-panel [data-ai-draft-target='status']", text: /Grok revised the draft/
      assert_field "Editable working copy", with: revised
      assert_field "chat-text", with: original
      assert_button "Apply to message", disabled: false
      assert_equal 0, room.messages.count

      click_button "Apply to message"
      assert_field "chat-text", with: revised
      assert_equal 0, room.messages.count
      click_button "Undo applied edit"
      assert_field "chat-text", with: original
      assert_equal 0, room.messages.count
      assert_equal 1, page.evaluate_script("window.__grokFakeCalls")
    end
  end
end
