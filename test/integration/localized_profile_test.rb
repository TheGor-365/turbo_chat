# frozen_string_literal: true

require "test_helper"
require "json"

class LocalizedProfileTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "account settings use complete localized text while controls and identity remain unchanged" do
    user = users(:one)
    sign_in user
    original = user.reload.attributes.slice("email", "display_name", "share_presence", "updated_at")

    %w[en ru hy es].each do |locale|
      get edit_user_registration_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-account-heading h2",
        text: I18n.t("ui.nav.settings", locale: locale)
      assert_select "#profile-settings-title", text: I18n.t("ui.profile.section_profile", locale: locale)
      assert_select "#security-settings-title", text: I18n.t("ui.profile.security", locale: locale)
      assert_select "#presence-privacy-title", text: I18n.t("ui.profile.presence", locale: locale)
      assert_select "#notification-settings-title", text: I18n.t("ui.profile.notifications", locale: locale)
      assert_select "#account-removal-title", text: I18n.t("ui.profile.removal", locale: locale)
      assert_select "label[for=user_current_password]",
        text: I18n.t("ui.profile.current_password", locale: locale)
      assert_select "#presence-visibility-toggle[value=?]",
        I18n.t(user.share_presence? ? "ui.profile.appear_offline" : "ui.profile.show_active", locale: locale)
      assert_select "input[type=submit][value=?]",
        I18n.t("ui.profile.save", locale: locale), count: 1
      assert_select ".sd-settings-delete-link",
        text: I18n.t("ui.profile.delete_account", locale: locale), count: 1
      assert_select "form.sd-account-form[data-avatar-preview-messages-value]" do |nodes|
        messages = JSON.parse(nodes.first["data-avatar-preview-messages-value"])
        assert_equal I18n.t("ui.profile.avatar_js_size", locale: locale),
          messages.fetch("too_large")
        assert_equal I18n.t("ui.profile.avatar_js_selected", locale: locale),
          messages.fetch("selected")
      end
      assert_select "#user_email[value=?]", user.email
    end

    assert_equal original, user.reload.attributes.slice("email", "display_name", "share_presence", "updated_at")
  end
end
