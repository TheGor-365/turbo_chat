require "test_helper"

class LocalizedRoomSettingsSecondaryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "room settings secondary labels preserve message and translation state across UI languages" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice,bob], "private_#{[alice.id,bob.id].sort.join('_')}")
    sign_in alice
    count = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "#incoming-translation-heading", text: I18n.t("ui.chat_compose.incoming_title", locale: locale)
      assert_select ".sd-chat-simple-preferences strong", text: I18n.t("ui.chat_compose.detailed", locale: locale)
      assert_select ".sd-chat-translation-settings select[data-incoming-translation-target=locale]", count: 1
      assert_select "input[data-incoming-translation-target=toggle][type=checkbox]", count: 1
      assert_select "#chat-text", count: 1
    end
    assert_equal count, Message.count
  end
end
