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
end
