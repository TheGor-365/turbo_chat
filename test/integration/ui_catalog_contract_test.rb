# frozen_string_literal: true
require "test_helper"
require "yaml"

class UiCatalogContractTest < ActiveSupport::TestCase
  LOCALES = %w[en ru hy es].freeze

  def leaves(value, path = [], result = {})
    value.each do |name, item|
      keys = path + [name]
      item.is_a?(Hash) ? leaves(item, keys, result) : result[keys.join(".")] = item
    end
    result
  end

  def ui(locale)
    YAML.safe_load_file(Rails.root.join("config/locales/ui.#{locale}.yml"))
      .fetch(locale).fetch("ui")
  end

  test "four dictionaries have matching keys, nonempty copy and interpolation parameters" do
    assert_equal :en, I18n.default_locale
    assert_equal LOCALES.sort, I18n.available_locales.map(&:to_s).sort
    english = leaves(ui("en"))
    LOCALES.each do |locale|
      translations = leaves(ui(locale))
      assert_equal english.keys.sort, translations.keys.sort, "#{locale}: key mismatch"
      english.each do |key, original|
        translated = translations.fetch(key)
        assert_kind_of String, translated, "#{locale}: #{key}"
        assert translated.strip.present?, "#{locale}: #{key} blank"
        tokens = ->(text) { text.scan(/%\{([a-zA-Z_]+)\}/).flatten.sort }
        assert_equal tokens.call(original), tokens.call(translated),
          "#{locale}: #{key} interpolation mismatch"
      end
    end
  end
end
