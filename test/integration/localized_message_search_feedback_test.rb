# frozen_string_literal: true
require "test_helper"

class LocalizedMessageSearchFeedbackTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "Stimulus receives locale-specific feedback without changing search URL or draft state" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice
    before = [Room.count, Message.count]

    %w[en ru hy es].each do |locale|
      get room_path(room), params: { ui_locale: locale }
      assert_response :success
      assert_select ".message-search-shell[data-message-search-url-value=?]", search_room_messages_path(room) do
        %w[searching rate_limit unavailable invalid_results connection_error].each do |key|
          attribute = "data-message-search-#{key.tr('_', '-')}-text-value"
          assert_select "[#{attribute}=?]", I18n.t("ui.message_search.#{key}", locale: locale)
        end
      end
      assert_select "#chat-text"
      assert_select "form.message-composer", count: 1
    end
    assert_equal before, [Room.count, Message.count]
  end
end
