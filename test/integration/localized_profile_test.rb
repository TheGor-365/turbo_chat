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
      assert_select ".sd-account-heading h2", count: 0
      assert_select ".sd-settings-section[aria-label=?]",
        I18n.t("ui.profile.section_profile", locale: locale), count: 1
      assert_select ".sd-mobile-bottom-nav a[href=?]",
        edit_user_registration_path, text: I18n.t("ui.mobile_nav.profile", locale: locale), count: 1
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
  test "room has translated latest message state and private-group membership labels" do
    user = users(:one)
    group = Room.create!(name: "G1 B14 Localized Group", kind: "private_group",
      is_private: true, owner: user)
    group.participants.create!(user: user, group_role: "owner")
    sign_in user

    %w[en ru hy es].each do |locale|
      get room_path(group), params: {ui_locale: locale}
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select "#single_room[data-scroll-latest-text-value=?]",
        I18n.t("ui.conversation.latest", locale: locale), count: 1
      assert_select "#single_room[data-scroll-new-text-value=?]",
        I18n.t("ui.conversation.new_count", locale: locale), count: 1
      assert_select "#private-group-details[aria-label=?]",
        I18n.t("ui.group_popover.membership", locale: locale), count: 1
      assert_select ".sd-private-group-details__heading strong",
        text: I18n.t("ui.group_popover.members", locale: locale)
    end
  end
end
