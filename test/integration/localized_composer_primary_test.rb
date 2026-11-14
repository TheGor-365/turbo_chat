require "test_helper"

class LocalizedComposerPrimaryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "composer primary input and writing panels follow locale and preserve room" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id,bob.id].sort.join('_')}")
    sign_in alice
    count = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "#chat-text[placeholder=?]", I18n.t("ui.chat_compose.write_message", locale: locale)
      assert_select "button.composer-send[aria-label=?]", I18n.t("ui.chat_compose.send", locale: locale)
      assert_select "#ai-room-option-title", text: I18n.t("ui.chat_compose.assistance", locale: locale)
      assert_select "#ai-draft-actions-heading", text: I18n.t("ui.chat_compose.ai_actions", locale: locale)
      assert_select "button.sd-ai-draft-preset", count: 12
      assert_select "[data-ai-draft-copy-value]" do |nodes|
        copy = JSON.parse(nodes.first["data-ai-draft-copy-value"])
        %w[on off aria_spellcheck aria_manual_available aria_ai_off aria_auto_off aria_source_include aria_source_open].each do |key|
          assert_equal I18n.t("ui.chat_runtime.ai.#{key}", locale: locale), copy.fetch(key)
        end
      end
      assert_select "[data-ai-draft-target=autoIndicator]", text: I18n.t("ui.chat_runtime.ai.status_auto_off", locale: locale)
      assert_select "[data-ai-draft-target=spellIndicatorLabel]", text: I18n.t("ui.chat_runtime.ai.spell_on", locale: locale)
      assert_select "[data-ai-draft-target=spellState]", text: I18n.t("ui.chat_runtime.ai.on", locale: locale)
      assert_select ".sd-ai-room-option--auto .sd-ai-room-switch span:last-child", text: I18n.t("ui.chat_runtime.ai.off", locale: locale)
    end
    assert_equal count, Message.count
  end


  test "context task selector follows locale when consent-gated AI tools are enabled in test" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice
    previous = Message.count

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        %w[en ru hy es].each do |locale|
          get room_path(room), params: { ui_locale: locale }
          assert_response :success
          assert_select "#ai-context-task-kind option[value='']",
            text: I18n.t("ui.chat_compose.choose_task", locale: locale)
          assert_select "#ai-context-task-kind option[value='client_brief']",
            text: I18n.t("ui.chat_compose.client_brief", locale: locale)
          assert_select ".sd-h4-composer-link[title=?]",
            I18n.t("ui.chat_compose.review_task", locale: locale)
        end
      end
    end
    assert_equal previous, Message.count
  end
end
