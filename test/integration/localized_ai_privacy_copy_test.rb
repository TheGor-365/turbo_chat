require "test_helper"
class LocalizedAiPrivacyCopyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "manual AI privacy disclosures are localized and never trigger requests on render" do
    sign_in users(:one)
    room = rooms(:one)
    before = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select ".sd-ai-provider-details", text: /#{Regexp.escape(I18n.t("ui.chat_compose.draft_first", locale: locale))}/
      assert_select "#chat-text", count: 1
    end
    assert_equal before, Message.count
  end
end
