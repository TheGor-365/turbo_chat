# frozen_string_literal: true
require "test_helper"

class LocalizedActivityShellTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "activity search shell and native filter values translate without account changes" do
    sign_in users(:one)
    before = [Room.count, Message.count]
    %w[en ru hy es].each do |locale|
      get notifications_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "#notification-center-title", text: I18n.t("ui.activity_history.title", locale: locale)
      assert_select "#archive-title", text: I18n.t("ui.activity_history.search_title", locale: locale)
      assert_select "#archive-query[placeholder=?]", I18n.t("ui.activity_history.search_placeholder", locale: locale)
      assert_select "#archive-room option[value='']", text: I18n.t("ui.activity_history.all_conversations", locale: locale)
      assert_select "#archive-period option[value=month]", text: I18n.t("ui.activity_history.periods.month", locale: locale)
      assert_select ".sd-archive-kinds a", text: I18n.t("ui.activity_history.types.images", locale: locale)
      get notifications_path, params: { ui_locale: locale, kind: "images", period: "month" }
      assert_response :success
      assert_select "nav.sd-archive-kinds a.is-active", text: I18n.t("ui.activity_history.types.images", locale: locale)
      assert_select "#archive-period option[value=month][selected]"
    end
    assert_equal before, [Room.count, Message.count]
  end
end
