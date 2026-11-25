# frozen_string_literal: true
require "test_helper"

class AiWorkspaceMessageOriginLocaleTest < ActiveSupport::TestCase
  test "all display kinds have distinct localized labels without English fallback" do
    kinds = ["manual", "unknown", *AiWorkspace::MessageOrigin::VERIFIED_WORKFLOWS.values].uniq
    %i[en ru hy es].each do |locale|
      labels = kinds.map do |kind|
        key = "ui.chat_messages.origin.#{kind}"
        assert I18n.exists?(key, locale, fallback: false), "#{locale}: #{key}"
        label = I18n.t(key, locale: locale, fallback: false, raise: true)
        assert_kind_of String, label
        assert label.present?, "#{locale}: #{key}"
        label
      end
      assert_equal kinds.size, labels.uniq.size, "#{locale}: indistinguishable origins"
    end
  end
end
