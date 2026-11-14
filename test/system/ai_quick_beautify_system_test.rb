require "application_system_test_case"
require "minitest/mock"

class AiQuickBeautifySystemTest < ApplicationSystemTestCase
  def sign_in(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  test "one click yields editable inline versions, Apply, Undo, but never a Send" do
    original = "I has received document and will answer tomorow."
    improved = "I have received the document and will answer tomorrow."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: original
      page.execute_script(<<~JS)
        window.__quickCalls = 0
        window.fetch = async (_url, options) => {
          window.__quickCalls++
          window.__quickPayload = JSON.parse(options.body)
          return {ok: true, json: async () => ({text: #{improved.to_json}, cost_usd:"0.000208"})}
        }
      JS
      click_button "Beautify with Grok — one paid request per click ($0.10 local reserve; actual cost may vary)"
      assert_selector ".sd-quick-beautify-panel:not([hidden])", text: /Compare and choose/, wait: 10
      assert_selector ".sd-quick-beautify-original", text: original
      assert_field "AI version (editable)", with: improved
      assert_field "chat-text", with: original
      assert_equal 1, page.evaluate_script("window.__quickCalls")
      assert_equal "polish_clarity", page.evaluate_script("window.__quickPayload.draft.preset_id")
      assert_equal "1", page.evaluate_script("window.__quickPayload.draft.consent")
      assert_equal 0, room.messages.count
      click_button "Use AI version"
      assert_field "chat-text", with: improved
      assert_button "Undo applied AI edit"
      click_button "Undo applied AI edit"
      assert_field "chat-text", with: original
      assert_equal 0, room.messages.count
    end
  end

  test "stale asynchronous AI cannot overwrite newly typed text" do
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: "Original draft for quick review."
      page.execute_script(<<~JS)
        window.__quickCalls = 0
        window.fetch = async () => {
          window.__quickCalls++
          return await new Promise(resolve => {window.__resolveQuick = resolve})
        }
      JS
      click_button "Beautify with Grok — one paid request per click ($0.10 local reserve; actual cost may vary)"
      assert_selector ".sd-quick-beautify-panel:not([hidden])", text: /paid Grok request/
      fill_in "chat-text", with: "A new manually edited draft while AI is still working."
      page.execute_script('window.__resolveQuick({ok:true,json:async()=>({text:"Old AI result",cost_usd:"0.0001"})})')
      assert_selector ".sd-quick-beautify-panel", text: /outdated AI output discarded/
      assert_button "Use AI version", disabled: true
      assert_field "chat-text", with: "A new manually edited draft while AI is still working."
      assert_equal 1, page.evaluate_script("window.__quickCalls")
      assert_equal 0, room.messages.count
    end
  end
end
