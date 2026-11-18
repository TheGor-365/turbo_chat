# frozen_string_literal: true
require "test_helper"

class LocalizedActivityContentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "notification feed and authorized search results translate without marking messages read" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: bob, body: "archive-locale-message-57")
    note = Notification.find_by!(user: alice, message: message)
    sign_in alice

    %w[en ru hy es].each do |locale|
      get notifications_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "#activity-feed-title", text: I18n.t("ui.activity_history.activity", locale: locale)
      assert_select "#chat-history-title", text: I18n.t("ui.activity_history.chat_history", locale: locale)
      assert_select "#notification-list [data-notification-id=?]", note.id.to_s do
        assert_select ".sd-activity-event__body span",
          text: I18n.t("ui.room_list.last_message", locale: locale, name: bob.chat_label)
      end
      assert_not_includes response.body, message.body
      assert_nil note.reload.read_at

      get notifications_path, params: { ui_locale: locale, q: "archive-locale-message-57" }
      assert_response :success
      assert_select "#archive-results [data-archive-message-id=?]", message.id.to_s
      assert_select "#archive-results a[aria-label=?][href=?]",
        I18n.t("ui.activity_history.open_message", locale: locale),
        room_path(room, focus: message.id)
      assert_nil note.reload.read_at
    end
  end

  test "search validation errors translate and do not change room memberships" do
    sign_in users(:one)
    before = [Room.count, Message.count]
    %w[en ru hy es].each do |locale|
      get notifications_path, params: { ui_locale: locale, q: "x" }
      assert_response :success
      assert_select ".sd-archive-search-error",
        text: I18n.t("ui.activity_history.error_short", locale: locale)
    end
    assert_equal before, [Room.count, Message.count]
  end
end
