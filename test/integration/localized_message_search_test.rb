# frozen_string_literal: true
require "test_helper"

class LocalizedMessageSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "room-scoped search and paging labels follow four interface locales" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: bob, body: "locale-search-target-849")
    sign_in alice
    baseline = Message.count

    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "#message-search-panel input[placeholder=?]",
        I18n.t("ui.message_search.placeholder", locale: locale)
      assert_select ".sd-command-trigger[aria-label=?]",
        I18n.t("ui.message_search.search", locale: locale)

      get search_room_messages_path(room), params: { ui_locale: locale, q: "locale-search-target" }
      assert_response :success
      assert_select "turbo-frame#message_search_results"
      assert_select ".message-search-hit[aria-label=?][href=?]",
        I18n.t("ui.message_search.open_named", locale: locale, id: message.id),
        room_path(room, focus: message.id)
      assert_select ".message-search-open", text: /#{Regexp.escape(I18n.t("ui.message_search.open_message", locale: locale))}/

      get search_room_messages_path(room), params: { ui_locale: locale, q: "x" }
      assert_response :success
      assert_select ".message-search-empty", text: I18n.t("ui.message_search.min_characters", locale: locale)
    end
    assert_equal baseline, Message.count
  end
end
