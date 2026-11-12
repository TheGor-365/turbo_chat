require "application_system_test_case"
require "warden/test/helpers"

class IncomingTranslationChatTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @jack = users(:one)
    @eric = users(:two)
    @room = Room.create_private_room([@jack, @eric],
      "private_#{[@jack.id, @eric.id].sort.join('_')}")
    @original = "Hello, please send the updated landing page tomorrow."
    @message = @room.messages.create!(user: @eric, body: @original)
    Warden.test_mode!
    login_as @jack, scope: :user
  end

  teardown { Warden.test_reset! }

  test "default is plain chat; expanded tools are opt-in and persist per browser" do
    visit room_path(@room)
    assert_selector "#chat-text"
    assert_no_selector ".sd-ai-room-strip", visible: true
    assert_selector ".sd-message", text: @original

    click_button "Edit unsent message"
    within("#ai-draft-panel") { click_button "Room settings" }
    assert_selector "#ai-room-settings .sd-chat-simple-preferences", visible: true
    find("input[data-simple-chat-target='detailToggle']").check
    assert_selector ".sd-ai-room-strip", visible: true
    assert_equal "detailed", page.evaluate_script("document.body.dataset.chatUiMode")
    find("input[data-simple-chat-target='detailToggle']").uncheck
    assert_no_selector ".sd-ai-room-strip", visible: true
    assert_equal "simple", page.evaluate_script("document.body.dataset.chatUiMode")
    click_button "Close writing settings"

    visit room_path(@room)
    assert_equal "simple", page.evaluate_script("document.body.dataset.chatUiMode")
    assert_equal @original, @message.reload.body
  end

  test "opt-in local translator shows a text-only translation, the original, and never changes message" do
    visit room_path(@room)
    # Stub the browser API, not the Rails AI gateway, so this test never
    # downloads a model or performs a paid HTTP request.
    page.execute_script(<<~JS)
      Object.defineProperty(window, "Translator", {
        configurable: true,
        value: {
          create: ({sourceLanguage, targetLanguage}) =>
            Promise.resolve({
              translate: text => Promise.resolve("Пожалуйста, пришлите обновлённый лендинг завтра."),
              destroy: () => {}
            })
        }
      })
    JS

    click_button "Edit unsent message"
    within("#ai-draft-panel") { click_button "Room settings" }

    # Source language is explicit, so test is deterministic without downloads
    # from Chrome's LanguageDetector model.
    find("details.sd-chat-translation-settings__advanced > summary").click
    find("select[data-incoming-translation-target='source']").find("option[value='en']").select_option
    find("input[data-incoming-translation-target='toggle']").check

    assert_selector ".sd-incoming-translated__text",
      text: "Пожалуйста, пришлите обновлённый лендинг завтра.", wait: 10
    assert_selector ".sd-incoming-translated__badge", text: "EN → RU"
    assert_equal @original, @message.reload.body

    click_button "Close writing settings"
    find(".sd-incoming-original summary").click
    assert_selector ".sd-incoming-original[open]", text: @original
    assert_equal @original, @message.reload.body

    click_button "Edit unsent message"
    within("#ai-draft-panel") { click_button "Room settings" }
    find("input[data-incoming-translation-target='toggle']").uncheck
    assert_no_selector ".sd-incoming-translated"
    assert_selector ".sd-message-original", text: @original
    assert_equal @original, @message.reload.body
  end

  test "unsupported browser preserves original and explains limitation in settings" do
    visit room_path(@room)
    page.execute_script('Object.defineProperty(window, "Translator", {configurable:true,value:undefined})')
    click_button "Edit unsent message"
    within("#ai-draft-panel") { click_button "Room settings" }
    find("input[data-incoming-translation-target='toggle']").check
    assert_selector ".sd-chat-translation-settings__status",
      text: /не поддерживает локальный AI-перевод/
    assert_no_selector ".sd-incoming-translated"
    assert_equal @original, @message.reload.body
  end
end
