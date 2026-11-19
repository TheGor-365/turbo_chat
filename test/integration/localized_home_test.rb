# frozen_string_literal: true

require "test_helper"

class LocalizedHomeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  LOCALES = %w[en ru hy es].freeze

  test "all guest home content translates and the selected locale is retained" do
    LOCALES.each do |locale|
      get root_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "body[data-ui-locale=?]", locale
      assert_select ".sd-home-hero--guest h1",
        text: I18n.t("ui.guest.title", locale: locale)
      assert_select ".sd-home-intro .sd-home-intro__row", count: 3
      assert_select ".sd-home-intro .sd-home-intro__row strong",
        text: /#{Regexp.escape(I18n.t("ui.guest.step_connect", locale: locale))}/
      assert_select "#home-features-title",
        text: I18n.t("ui.guest.available", locale: locale)
      assert_select ".sd-home-feature h3",
        text: I18n.t("ui.guest.deliverables", locale: locale)
      get root_path
      assert_select "html[lang=?]", locale
      assert_select ".sd-home-hero--guest h1",
        text: I18n.t("ui.guest.title", locale: locale)
    end
  end

  test "signed-in home localizes titles, actions and room kinds without changing membership" do
    member, peer = users(:one), users(:two)
    direct = Room.create_private_room([member, peer],
      "private_#{[member.id, peer.id].sort.join('_')}")
    direct.messages.create!(user: peer, body: "Private phrase must not render on Home")
    sign_in member

    LOCALES.each do |locale|
      get root_path, params: { ui_locale: locale }
      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_select "html[lang=?]", locale
      assert_select "#home-title", text: I18n.t("ui.home.title", locale: locale)
      assert_select "#home-recent-title", text: I18n.t("ui.home.recent", locale: locale)
      assert_select "#home-shortcuts-title", text: I18n.t("ui.home.quick", locale: locale)
      assert_select ".sd-home-actions .sd-home-button--primary",
        text: I18n.t("ui.home.continue", locale: locale)
      assert_select ".sd-home-attention__content span",
        text: I18n.t("ui.home.unread_alerts", locale: locale)
      assert_select ".sd-home-room[href=?]", room_path(direct), count: 1
      assert_select ".sd-home-room[href=?] .sd-home-room__body span",
        room_path(direct),
        text: I18n.t("ui.home.room_types.direct", locale: locale)
      assert_not_includes response.body, "Private phrase must not render on Home"
    end
    assert_equal 1, direct.messages.reload.count
  end
end
