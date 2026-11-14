# frozen_string_literal: true
require "test_helper"
require "json"

class UiLocaleShellTest < ActionDispatch::IntegrationTest
  test "navigation, document language and theme labels are localized" do
    %w[en ru hy es].each do |locale|
      get new_user_session_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "body[data-ui-locale=?]", locale
      assert_select "nav[aria-label=?]", I18n.t("ui.nav.main", locale: locale)
      assert_select "body[data-ui-theme-labels]" do |nodes|
        states = JSON.parse(nodes.first["data-ui-theme-labels"])
        assert_equal %w[dark light system], states.keys.sort
        assert_equal I18n.t("ui.nav.theme_aria", locale: locale,
          current: I18n.t("ui.nav.theme_modes.dark", locale: locale),
          next: I18n.t("ui.nav.theme_modes.light", locale: locale)),
          states.fetch("dark").fetch("aria")
      end
    end
  end
end
