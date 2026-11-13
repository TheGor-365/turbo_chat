require "test_helper"

class LocalizedAiPanelSecondaryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "message composer and AI panel secondary controls use server locale" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id,bob.id].sort.join('_')}")
    sign_in alice
    count = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select ".composer-drop-hint", text: I18n.t("ui.chat_compose.drop", locale: locale)
      assert_select "#ai-room-settings .sd-ai-room-context-label", text: I18n.t("ui.chat_compose.room", locale: locale)
      assert_select "#ai-draft-panel .sd-ai-draft-edit-label", text: /#{Regexp.escape(I18n.t("ui.chat_compose.editable_copy", locale: locale))}/
      assert_select "#ai-draft-panel .sd-ai-deliverable-preview__summary strong", text: I18n.t("ui.chat_compose.formatted", locale: locale)
      assert_select ".sd-ai-custom-instructions__save input#ai-custom-template-name"
      assert_select "#message_attachments", count: 1
    end
    assert_equal count, Message.count
  end
end
