require "test_helper"

class LocalizedIncomingTranslationCopyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  test "translation UI copy varies across four locales without enabling translation or changing room messages" do
    room = rooms(:one)
    sign_in users(:one)
    before = Message.count
    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select "#single_room[data-incoming-translation-copy-value]" do |nodes|
        copy = JSON.parse(nodes.first["data-incoming-translation-copy-value"])
        assert_equal I18n.t("ui.chat_runtime.incoming.disabled", locale: locale), copy.fetch("disabled")
        assert_equal I18n.t("ui.chat_runtime.incoming.translated", locale: locale), copy.fetch("translated")
      end
      assert_select "input[data-incoming-translation-target=toggle]:not(:checked)"
    end
    assert_equal before, Message.count
  end
end
