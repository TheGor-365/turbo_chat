# frozen_string_literal: true
require "test_helper"

class LocalizedConversationShellTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "room header and controls translate without changing room access or message content" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: bob, body: "CONVERSATION_SHELL_PRIVATE_CONTENT")
    sign_in alice
    before = [Message.count, Room.count]

    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "#single_room"
      assert_select ".sd-conversation-tools__trigger[aria-label=?]",
        I18n.t("ui.conversation.tools", locale: locale)
      assert_select "#conversation-tools-panel [data-realtime-health-target=syncButton][aria-label=?]",
        I18n.t("ui.conversation.sync", locale: locale)
      assert_select ".room-notification-preference button[aria-label=?]",
        I18n.t("ui.conversation.mute", locale: locale)
      assert_select "#message_#{message.id}", text: /CONVERSATION_SHELL_PRIVATE_CONTENT/
      assert_select "#chat-text"
      assert_select "#single_room[data-room-read-url-value=?]", read_room_path(room)
    end
    assert_equal before, [Message.count, Room.count]
  end

  test "focused-message route keeps historical context and localized return link" do
    user = users(:one)
    room = rooms(:one)
    message = room.messages.create!(user: user, body: "historical-locale-focus")
    sign_in user
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { focus: message.id, ui_locale: locale }
      assert_response :success
      assert_select ".message-focus-banner strong",
        text: I18n.t("ui.conversation.older_title", locale: locale)
      assert_select ".message-focus-return[href=?]",
        room_path(room), text: I18n.t("ui.conversation.return_latest", locale: locale)
    end
  end
end
