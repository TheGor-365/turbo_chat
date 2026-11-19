# frozen_string_literal: true

require "test_helper"

class LocalizedSidebarShellTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "inbox sidebar controls localize in four languages without altering routes or room names" do
    user = users(:one)
    sign_in user
    before_rooms = Room.count

    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale, space: "private" }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "#sd-users-title span", text: I18n.t("ui.inbox.find_people", locale: locale)
      assert_select "#side_panel form.sd-people-search input[placeholder=?]",
        I18n.t("ui.inbox.search_people_placeholder", locale: locale)
      assert_select "#side_panel form.sd-people-search button[aria-label=?]",
        I18n.t("ui.inbox.search_people", locale: locale)
      assert_select "#inbox-filters .sd-segment__item", text: I18n.t("ui.inbox.all", locale: locale)
      assert_select "#inbox-filters .sd-segment__item", text: I18n.t("ui.inbox.unread", locale: locale)
      assert_select "#sd-direct-title", text: /#{Regexp.escape(I18n.t("ui.inbox.direct", locale: locale))}/
      assert_select "#sd-spaces-title", text: /#{Regexp.escape(I18n.t("ui.inbox.rooms", locale: locale))}/
      assert_select ".sd-spaces-switch [aria-label=?]", I18n.t("ui.inbox.private_rooms", locale: locale)
      assert_select "#sd-private-pane input[aria-label=?]",
        I18n.t("ui.inbox.new_private_group_name", locale: locale)
      assert_select "#sd-private-pane button[aria-label=?]",
        I18n.t("ui.inbox.create_private_group", locale: locale)
      assert_select "#sd-private-pane [aria-label=?]",
        I18n.t("ui.inbox.joined_private_rooms", locale: locale)
      assert_select "#side_panel a[href=?]", edit_user_registration_path
      assert_select "#sd-public-pane form#room_search_form"
      assert_select "#sd-private-pane form#private_room_search_form"
    end
    assert_equal before_rooms, Room.count
  end

  test "inbox people search retains the user's query and localizes no-results status" do
    sign_in users(:one)
    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale, people: "unlikely-name-17424" }
      assert_response :success
      assert_select "#side_panel form.sd-people-search input[name=people][value=?]", "unlikely-name-17424"
      assert_select "#users p[role=status]", text: I18n.t("ui.inbox.no_people", locale: locale)
      assert_select "#side_panel .sd-directory-search__reset[aria-label=?]",
        I18n.t("ui.inbox.clear_people_search", locale: locale)
    end
  end
end
