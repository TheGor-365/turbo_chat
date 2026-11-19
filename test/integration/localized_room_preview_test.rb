# frozen_string_literal: true
require "test_helper"
require "yaml"

class LocalizedRoomPreviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "preview and relative timestamp follow the chosen locale and never show message body" do
    author = users(:one)
    room = Room.create!(name: "i18n-room-preview")
    room.joinables.create!(user: author)
    secret = "PREVIEW_BODY_MUST_REMAIN_HIDDEN_2026"
    message = room.messages.create!(user: author, body: secret, created_at: 3.days.ago)
    sign_in author
    before_messages = Message.count

    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "#rooms .sd-room-entry__preview-text",
        text: I18n.t("ui.room_list.last_message", locale: locale, name: author.chat_label).truncate(40)
      expected_time = I18n.t("ui.room_list.ago", locale: locale,
        distance: I18n.t("datetime.distance_in_words.x_days", locale: locale, count: 3))
      assert_select "#rooms time[datetime=?]", message.created_at.iso8601, text: expected_time
      assert_not_includes response.body, secret
      get inbox_rooms_path, as: :json
      json = JSON.parse(response.body)
      assert_includes json.fetch("public"), expected_time
      assert_not_includes json.fetch("public"), secret
    end
    assert_equal before_messages, Message.count
  end

  test "distance catalogs agree on the same keys and interpolation tokens" do
    reference = YAML.safe_load_file(Rails.root.join("config/locales/relative_distance.en.yml"))
      .fetch("en").fetch("datetime").fetch("distance_in_words")
    %w[ru hy es].each do |locale|
      copy = YAML.safe_load_file(Rails.root.join("config/locales/relative_distance.#{locale}.yml"))
        .fetch(locale).fetch("datetime").fetch("distance_in_words")
      assert_equal reference.keys.sort, copy.keys.sort
      reference.each do |key, value|
        expected = value.is_a?(Hash) ? value.keys : []
        actual = copy.fetch(key)
        assert_equal expected.sort, (actual.is_a?(Hash) ? actual.keys.sort : []),
          "#{locale}.#{key} plural keys"
      end
    end
  end
end
