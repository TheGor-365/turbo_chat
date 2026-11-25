require "test_helper"
class LocalizedMessageBubbleContractTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "message UI labels translate, message bodies remain unchanged" do
    user = users(:one)
    room = rooms(:one)
    message = room.messages.create!(user: user, body: "USER_AUTHORED_MESSAGE_UNTRANSLATED")
    sign_in user
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "#message_#{message.id}", text: /USER_AUTHORED_MESSAGE_UNTRANSLATED/
      assert_select "#message_#{message.id} .sd-message-action-trigger[aria-label=?]",
        I18n.t("ui.chat_messages.actions", locale: locale)
      assert_select "#message_#{message.id} .sd-message-bubble small"
      assert_includes response.body, I18n.t("ui.chat_messages.ago", locale: locale, time: "TEST_MARKER").delete_prefix("TEST_MARKER") if locale == "ru"
    end
    assert_equal "USER_AUTHORED_MESSAGE_UNTRANSLATED", message.reload.body
  end

  test "six origin badges stay localized in the initial message render" do
    actor = users(:one)
    room = rooms(:one)
    kinds = {
      "manual" => ["manual", false],
      "ai_edited" => ["ai_edited", true],
      "ai_generated" => ["ai_generated", true],
      "ai_assisted_legacy" => [nil, true],
      "synthetic" => ["synthetic", true],
      "unknown" => [nil, false]
    }
    records = kinds.transform_values.with_index do |(origin, assisted), index|
      room.messages.create!(user: actor, body: "Origin fixture #{index}",
        origin: origin, ai_assisted: assisted)
    end
    sign_in actor

    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      records.each do |kind, message|
        assert_select "#message_#{message.id} .sd-message-origin-mark[data-message-origin=?][role=img][aria-label=?]",
          kind, I18n.t("ui.chat_messages.origin.#{kind}", locale: locale), count: 1
      end
    end
  end

  test "HTTP sync append and replace preserve verified origin after editing" do
    actor = users(:one)
    room = rooms(:one)
    previous = room.messages.create!(user: actor, body: "Cursor marker", origin: "manual")
    generated = room.messages.create!(user: actor, body: "Proposed AI result",
      origin: "ai_generated", ai_assisted: true)
    version = (generated.updated_at.to_r * 1_000_000).to_i
    sign_in actor

    get sync_room_messages_path(room), params: { after_id: previous.id }
    assert_response :success
    assert_select 'turbo-stream[action="append"][target="messages-container"]', count: 1
    assert_includes response.body, 'data-message-origin="ai_generated"'
    assert_includes response.body, I18n.t("ui.chat_messages.origin.ai_generated")

    generated.update!(body: "Human corrected the generated result")
    get sync_room_messages_path(room), params: {
      after_id: generated.id, recheck: "#{generated.id}:#{version}"
    }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "message_#{generated.id}", count: 1
    assert_includes response.body, 'data-message-origin="ai_generated"'
    assert_includes response.body, "Human corrected the generated result"
    assert_equal "ai_generated", generated.reload.origin
    assert generated.ai_assisted?
  end

end
