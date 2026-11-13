# frozen_string_literal: true
require "test_helper"
require "yaml"

class DeviseTranslationContractTest < ActionDispatch::IntegrationTest
  def flatten(value, keys = [], result = {})
    value.each do |key, nested|
      path = keys + [key]
      nested.is_a?(Hash) ? flatten(nested, path, result) : result[path.join(".")] = nested
    end
    result
  end

  def catalog(locale)
    YAML.safe_load_file(Rails.root.join("config/locales/devise.#{locale}.yml")).fetch(locale)
  end

  test "Devise translations preserve all keys and interpolation arguments" do
    english = flatten(catalog("en"))
    %w[ru hy es].each do |locale|
      translated = flatten(catalog(locale))
      assert_equal english.keys.sort, translated.keys.sort, "#{locale} devise keys differ"
      english.each do |key, original|
        copy = translated.fetch(key)
        assert_kind_of String, copy
        assert copy.strip.present?, "#{locale}.#{key} is empty"
        tokens = ->(s) { s.scan(/%\{([a-zA-Z_]+)\}/).flatten.sort }
        assert_equal tokens.call(original), tokens.call(copy),
          "#{locale}.#{key} placeholders differ"
      end
    end
  end

  test "reset password edit form renders localized labels without mutating tokens" do
    %w[en ru hy es].each do |locale|
      get edit_user_password_path, params: { ui_locale: locale, reset_password_token: "invalid-token-preview" }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1", text: I18n.t("ui.auth.reset_title", locale: locale)
      assert_select 'label[for=user_password]', text: I18n.t("ui.profile.new_password", locale: locale)
      assert_select 'input[type=submit][value=?]', I18n.t("ui.auth.change_password", locale: locale)
      assert_select 'input[name="user[reset_password_token]"][type=hidden][value="invalid-token-preview"]', count: 1
    end
  end
end
