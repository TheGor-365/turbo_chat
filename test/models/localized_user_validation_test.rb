# frozen_string_literal: true

require "test_helper"
require "stringio"
require "yaml"

class LocalizedUserValidationTest < ActiveSupport::TestCase
  LOCALES = %w[en ru hy es].freeze

  def leaves(node, parts = [], result = {})
    node.each do |name, child|
      next_parts = parts + [name]
      child.is_a?(Hash) ? leaves(child, next_parts, result) : result[next_parts.join(".")] = child
    end
    result
  end

  def catalog(locale)
    YAML.safe_load_file(Rails.root.join("config/locales/account_validation.#{locale}.yml"))
      .fetch(locale)
  end

  test "validation locales have matching keys and interpolation placeholders" do
    english = leaves(catalog("en"))
    LOCALES.each do |locale|
      values = leaves(catalog(locale))
      assert_equal english.keys.sort, values.keys.sort, "#{locale} account validation keys differ"
      english.each do |key, reference|
        translated = values.fetch(key)
        assert_kind_of String, translated
        assert translated.strip.present?, "#{locale}: #{key} is empty"
        tokens = ->(value) { value.scan(/%\{([a-zA-Z_]+)\}/).flatten.sort }
        assert_equal tokens.call(reference), tokens.call(translated),
          "#{locale}: #{key} interpolation mismatch"
      end
    end
  end

  test "display name, email and password errors are translated in all four locales" do
    LOCALES.each do |locale|
      I18n.with_locale(locale) do
        user = User.new(
          email: "", password: "short", password_confirmation: "different",
          display_name: "invalid@example.test"
        )
        assert_not user.valid?, "Expected validation failure in #{locale}"
        # Rails FormatValidator retains :invalid as the details code;
        # its :invalid_characters message option chooses the localized text.
        assert_includes user.errors.details[:display_name].map { |error| error[:error] }, :invalid
        assert user.errors.details[:email].any?, "#{locale}: email error expected"
        assert user.errors.details[:password].any?, "#{locale}: password error expected"
        expected_name = I18n.t("activerecord.attributes.user.display_name")
        expected_message = I18n.t(
          "activerecord.errors.models.user.attributes.display_name.invalid_characters"
        )
        assert_includes user.errors.full_messages, "#{expected_name} #{expected_message}"
        assert_includes user.errors.full_messages.join(" "), I18n.t("activerecord.attributes.user.email")
        assert_not_match(/Translation missing|missing interpolation/i, user.errors.full_messages.join(" "))
      end
    end
  end

  test "avatar content type and size errors use typed localized messages" do
    LOCALES.each do |locale|
      I18n.with_locale(locale) do
        user = User.new(email: "image-#{locale}@example.test", password: "testing-secure-password-123")
        user.avatar.attach(
          io: StringIO.new("not an image"), filename: "wrong.html", content_type: "text/html"
        )
        assert_not user.valid?
        assert_includes user.errors.details[:avatar].map { |error| error[:error] }, :invalid_image
        assert_includes user.errors.full_messages,
          "#{User.human_attribute_name(:avatar)} #{I18n.t("activerecord.errors.models.user.attributes.avatar.invalid_image")}"
        user.avatar.detach
        user.avatar.attach(
          io: StringIO.new("x" * (5.megabytes + 1)),
          filename: "large.jpg", content_type: "image/jpeg"
        )
        assert_not user.valid?
        assert_includes user.errors.details[:avatar].map { |error| error[:error] }, :too_large
      end
    end
  end
end
