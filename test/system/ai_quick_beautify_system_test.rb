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

  def mock_beautify(source_text)
    proof = AiWorkspace::DraftProvenance.issue(
      actor: users(:one), room: room, source_text: source_text)
    page.execute_script(<<~JS)
      window.__grokCalls = 0
      window.__nativeChatFetch = window.fetch.bind(window)
      window.__aiEndpoint = document.querySelector(".msg-form").dataset.quickBeautifyUrl
      window.fetch = (url, options) => {
        if (String(url).includes(window.__aiEndpoint)) {
          window.__grokCalls++
          window.__lastGrokRequest = JSON.parse(options.body)
          return Promise.resolve({
            ok: true,
            json: async () => ({
              text: #{source_text.to_json},
              cost_usd: "0.000366",
              provenance_token: #{proof.to_json}
            })
          })
        }
        return window.__nativeChatFetch(url, options)
      }
    JS
  end

  def beautify
    click_button "Beautify with Grok — one paid request per click ($0.10 local reserve; actual cost may vary)"
  end

  test "AI arrow sends edited candidate, stamps provenance, and keeps two arrows separate" do
    original = "I has received document and will answer tomorow."
    improved = "I have received the document and will answer tomorrow."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: original
      mock_beautify(improved)
      beautify
      assert_selector ".sd-quick-beautify-panel:not([hidden])", wait: 10
      assert_field "AI version (editable)", with: improved
      assert_field "chat-text", with: original
      assert_no_selector ".sd-quick-beautify-original"
      assert_no_selector ".sd-quick-beautify-actions"
      assert_selector ".sd-quick-beautify-cost", text: "$0.000366"
      assert_no_selector ".sd-quick-beautify-status:not([hidden])", visible: :all
      assert_equal 1, page.evaluate_script("window.__grokCalls")
      assert_equal "polish_clarity", page.evaluate_script("window.__lastGrokRequest.draft.preset_id")
      assert_equal 0, room.messages.count
      fill_in "AI version (editable)", with: improved + " I will send an update."
      click_button "Send AI version"
      assert_selector ".sd-ai-message-mark[aria-label='AI-assisted']", wait: 10
      assert_equal 1, room.messages.count
      message = room.messages.order(:id).last
      assert_equal improved + " I will send an update.", message.body
      assert message.ai_assisted?
      assert_equal 1, page.evaluate_script("window.__grokCalls")
      assert_field "chat-text", with: ""
    end
  end

  test "manual arrow sends only the human text even with an available AI candidate" do
    original = "I has received document and will answer tomorow."
    improved = "I have received the document and will answer tomorrow."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: original
      mock_beautify(improved)
      beautify
      assert_field "AI version (editable)", with: improved
      assert_selector ".sd-quick-beautify-send:not(:disabled)"
      within("form.message-composer") { find("button.composer-send").click }
      assert_selector ".sd-message", text: original, wait: 10
      assert_equal 1, room.messages.count
      message = room.messages.order(:id).last
      assert_equal original, message.body
      assert_not message.ai_assisted?
      assert_no_selector "#message_#{message.id} .sd-ai-message-mark"
      assert_equal 1, page.evaluate_script("window.__grokCalls")
    end
  end

  test "a missing server attestation leaves AI Send disabled but manual Send available" do
    original = "I have a question about my Rails app."
    improved = "I have a question concerning my Rails application."
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: original
      page.execute_script(<<~JS)
        window.fetch = async () => ({
          ok: true, json: async () => ({
            text: #{improved.to_json}, cost_usd: "0.000366"
          })
        })
      JS
      beautify
      assert_field "AI version (editable)", with: improved
      assert_button "Send AI version", disabled: true
      assert_selector ".sd-quick-beautify-status", text: /cannot be verified/
      assert_field "chat-text", with: original
      assert_equal 0, room.messages.count
    end
  end

  test "stale async AI response never overwrites later manual typing" do
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: "Original draft for quick review."
      page.execute_script(<<~JS)
        window.__grokCalls = 0
        window.fetch = async () => {
          window.__grokCalls++
          return await new Promise(resolve => {window.__resolveGrok = resolve})
        }
      JS
      beautify
      assert_selector ".sd-quick-beautify-status", text: /paid Grok request/
      fill_in "chat-text", with: "A newer draft while the AI response is pending."
      page.execute_script(<<~JS)
        window.__resolveGrok({ok:true,json:async()=>({
          text:"Outdated suggested response", cost_usd:"0.000366",
          provenance_token:"signed-but-stale"
        })})
      JS
      assert_selector ".sd-quick-beautify-status", text: /outdated AI output discarded/
      assert_button "Send AI version", disabled: true
      assert_field "chat-text", with: "A newer draft while the AI response is pending."
      assert_equal 1, page.evaluate_script("window.__grokCalls")
      assert_equal 0, room.messages.count
    end
  end

  test "long versions expand independently and include touch-friendly resize controls" do
    original = (["A long human-authored paragraph with punctuation."] * 45).join(" ")
    improved = original.sub("paragraph", "document")
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      sign_in(users(:one))
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: original
      mock_beautify(improved)
      beautify
      assert_field "AI version (editable)", with: improved
      dimensions = page.evaluate_script(<<~JS)
        (() => {
          const human = document.querySelector("#chat-text")
          const ai = document.querySelector(".sd-quick-beautify-ai-row textarea")
          return [human.offsetHeight, ai.offsetHeight, window.innerHeight]
        })()
      JS
      assert_operator dimensions[0], :>, 100
      assert_operator dimensions[1], :>, 100
      assert_operator dimensions[0], :<=, dimensions[2] * 0.51
      assert_operator dimensions[1], :<=, dimensions[2] * 0.51
      click_button "Change AI text height"
      assert_in_delta window_height_fraction(0.46), field_height(".sd-quick-beautify-ai-row textarea"), 12
      click_button "Change my text height"
      assert_in_delta window_height_fraction(0.46), field_height("#chat-text"), 12
      assert_equal 0, room.messages.count
    end
  end

  private

  def window_height_fraction(fraction)
    page.evaluate_script("window.innerHeight") * fraction
  end

  def field_height(css)
    page.evaluate_script("document.querySelector(#{css.to_json}).getBoundingClientRect().height")
  end
end
