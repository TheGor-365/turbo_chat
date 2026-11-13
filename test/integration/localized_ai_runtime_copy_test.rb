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
        %w[context_ready_paid context_switch_off context_wait_all context_permission_error
          source_cleared source_access_denied template_invalid template_save_failed
          manual_working manual_preparing manual_suggested manual_failed applied_not_sent
          restored_not_sent brief_selected consent_changed_clear context_secure_missing
          context_note_limit context_source_expired context_rate_limit
          context_access_revoked context_provider_unavailable context_invalid_result
          context_late_result context_review_needed reported_cost context_room_sources
          context_omitted context_selected_reply context_generate_label].each do |key|
          assert_equal I18n.t("ui.chat_runtime.ai.#{key}", locale: locale), data.fetch(key)
        end
      end
    end
    assert_equal before, Message.count
  end
end
