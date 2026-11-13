require "test_helper"
class LocalizedAiRuntimeCopyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "AI controller gets locale-specific display strings and no chat messages are sent" do
    sign_in users(:one)
    room = rooms(:one)
    before = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select ".msg-form[data-ai-draft-copy-value]" do |elements|
        data = JSON.parse(elements.first["data-ai-draft-copy-value"])
        assert_equal I18n.t("ui.chat_runtime.ai.consent_ready", locale: locale), data.fetch("consent_ready")
        assert_equal I18n.t("ui.chat_runtime.ai.gen_polish", locale: locale), data.fetch("gen_polish")
      end
    end
    assert_equal before, Message.count
  end
end
