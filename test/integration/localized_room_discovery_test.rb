# frozen_string_literal: true
require "test_helper"

class LocalizedRoomDiscoveryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "public discovery, room creation form, and private search labels localize without changing routes" do
    user = users(:one)
    room = Room.create!(name: "aaa-i18n-catalogue-visible")
    sign_in user
    baseline = Room.count

    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale, space: "public" }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "#sd-public-pane input[placeholder=?]",
        I18n.t("ui.room_discovery.new_public_placeholder", locale: locale)
      assert_select "#sd-public-pane button[aria-label=?]",
        I18n.t("ui.room_discovery.create_public", locale: locale)
      assert_select "#room_search_form input[aria-label=?]",
        I18n.t("ui.room_discovery.search_scope.public", locale: locale)
      assert_select "#public-room-directory [aria-label=?]",
        I18n.t("ui.room_discovery.joinable_public", locale: locale)
      assert_select "#public-room-directory form[action=?]", join_room_path(room), count: 1
      assert_select "#public-room-directory button[aria-label=?]",
        I18n.t("ui.room_discovery.join_named", locale: locale, name: room.name)
      get rooms_path, params: { ui_locale: locale, space: "private" }
      assert_select "#private_room_search_form input[aria-label=?]",
        I18n.t("ui.room_discovery.search_scope.private", locale: locale)
      assert_select "#sd-private-pane form#private_room_search_form"
    end
    assert_equal baseline, Room.count
  end

  test "Turbo search responses honor previously selected language and do not expose unrelated rooms" do
    user = users(:one)
    visible = Room.create!(name: "i18n-room-search-match")
    sign_in user
    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale }
      post search_rooms_path, params: { space: "public", name_search: visible.name },
        as: :turbo_stream
      assert_response :success
      assert_includes response.body, visible.name
      assert_includes response.body,
        I18n.t("ui.room_discovery.join_named", locale: locale, name: visible.name)
      assert_not_includes response.body, "private_injected"
      post search_rooms_path, params: { space: "private", name_search: "not-a-member-of-this-group" },
        as: :turbo_stream
      assert_response :success
      assert_includes response.body, I18n.t("ui.room_discovery.private_no_results", locale: locale)
    end
  end
end
