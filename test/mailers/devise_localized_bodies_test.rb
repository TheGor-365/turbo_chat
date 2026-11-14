# frozen_string_literal: true
require "test_helper"
require "yaml"

class DeviseLocalizedBodiesTest < ActiveSupport::TestCase
  LOCALES = %w[en ru hy es].freeze

  def catalog(locale)
    YAML.safe_load_file(Rails.root.join("config/locales/devise_mailer_body.#{locale}.yml"))
      .fetch(locale).fetch("mailers").fetch("devise")
  end

  test "four email-body catalogs have the same keys and interpolation arguments" do
    english = catalog("en")
    LOCALES.each do |locale|
      translated = catalog(locale)
      assert_equal english.keys.sort, translated.keys.sort, "#{locale}: keys"
      english.each do |key, value|
        text = translated.fetch(key)
        assert text.is_a?(String) && text.present?, "#{locale}.#{key}"
        vars = ->(s) { s.scan(/%\{([a-zA-Z_]+)\}/).flatten.sort }
        assert_equal vars.call(value), vars.call(text), "#{locale}.#{key} placeholders"
      end
    end
  end

  test "password reset email is rendered in four languages without delivery or account writes" do
    user = users(:one)
    before_attributes = user.attributes.slice("email", "encrypted_password", "updated_at")
    previous_options = Devise.mailer.default_url_options.dup
    before_delivery = ActionMailer::Base.deliveries.size
    Devise.mailer.default_url_options = previous_options.merge(host: "example.test")

    LOCALES.each do |locale|
      I18n.with_locale(locale) do
        mail = Devise.mailer.reset_password_instructions(user, "test-reset-token").message
        assert_equal I18n.t("devise.mailer.reset_password_instructions.subject"), mail.subject
        body = Nokogiri::HTML(mail.body.decoded)
        assert_includes body.text, I18n.t("mailers.devise.hello", email: user.email)
        assert_includes body.text, I18n.t("mailers.devise.reset_ignore")
        link = body.at_css("a")
        assert link, "#{locale}: missing reset link"
        assert_equal I18n.t("mailers.devise.reset_link"), link.text
        assert_includes link["href"], "reset_password_token=test-reset-token"
        assert_includes link["href"], "example.test"
      end
    end
    assert_equal before_delivery, ActionMailer::Base.deliveries.size
    assert_equal before_attributes, user.reload.attributes.slice("email", "encrypted_password", "updated_at")
  ensure
    Devise.mailer.default_url_options = previous_options if previous_options
  end

  test "account change notifications render localized HTML without delivery" do
    user = users(:one)
    previous_options = Devise.mailer.default_url_options.dup
    before_delivery = ActionMailer::Base.deliveries.size
    Devise.mailer.default_url_options = previous_options.merge(host: "example.test")

    LOCALES.each do |locale|
      I18n.with_locale(locale) do
        samples = [
          [Devise.mailer.email_changed(user), "email_changed"],
          [Devise.mailer.password_change(user), "password_changed"]
        ]
        samples.each do |delivery, key|
          content = Nokogiri::HTML(delivery.message.body.decoded).text
          expected = key == "email_changed" ?
            I18n.t("mailers.devise.email_changed", email: user.email) :
            I18n.t("mailers.devise.#{key}")
          assert_includes content, expected
        end
      end
    end
    assert_equal before_delivery, ActionMailer::Base.deliveries.size
  ensure
    Devise.mailer.default_url_options = previous_options if previous_options
  end
end
