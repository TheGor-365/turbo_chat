require "test_helper"

class AccountAiWritingPreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def options(profile: "business", style: "professional_client_reply",
    language: "ru", tone: "professional")
    { profile_id: profile, writing_style: style, language: language, tone: tone }
  end

  test "unauthenticated calls never read or save defaults" do
    get account_ai_writing_preference_path
    assert_redirected_to new_user_session_path
    patch account_ai_writing_preference_path, params: { preference: options }, as: :json
    assert_response :unauthorized
    delete account_ai_writing_preference_path, as: :json
    assert_response :unauthorized
    assert_equal 0, AiAccountWritingPreference.count
  end

  test "personal account settings persist and only current account is writable" do
    sign_in @alice
    get account_ai_writing_preference_path
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_equal "private, no-store", response.headers["Cache-Control"]

    patch account_ai_writing_preference_path,
      params: {preference: options, user_id: @bob.id}, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("configured")
    assert_equal options.stringify_keys, response.parsed_body.fetch("preference")
    assert_equal 1, AiAccountWritingPreference.count
    assert_nil @bob.ai_account_writing_preference

    patch account_ai_writing_preference_path,
      params: {preference: options(profile: nil, style: "friendly", language: "es", tone: "warm")},
      as: :json
    assert_response :success
    assert_equal 1, AiAccountWritingPreference.count
    assert_equal "friendly", @alice.ai_account_writing_preference.reload.writing_style
    sign_out @alice
    sign_in @bob
    get account_ai_writing_preference_path
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
  end

  test "unknown, forged, incomplete and mismatched values fail without mutation" do
    sign_in @alice
    invalid = [
      options.merge(automatic_send: "true"),
      options.merge(writing_style: "dangerous_system_prompt"),
      options.merge(profile_id: "admin"),
      options.merge(language: "xx"),
      options.merge(tone: "owner"),
      options.merge(writing_style: "friendly"),
      {writing_style: "friendly"}
    ]
    invalid.each do |bad|
      patch account_ai_writing_preference_path, params: {preference: bad}, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, AiAccountWritingPreference.count

    patch account_ai_writing_preference_path,
      params: {preference: options(profile: "", style: "friendly", tone: "warm")},
      as: :json
    assert_response :success
    assert_nil @alice.ai_account_writing_preference.reload.profile_id
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
  end

  test "account defaults are inherited only by rooms without overrides" do
    sign_in @alice
    patch account_ai_writing_preference_path, params: {preference: options}, as: :json
    assert_response :success
    resolved = AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room)
    assert_equal "account", resolved.source
    assert_equal true, resolved.account_configured
    assert_equal false, resolved.room_configured
    assert_equal "ru", resolved.effective.fetch(:language)
    assert_equal "professional_client_reply", resolved.experience.settings.fetch(:writing_style)
    assert_equal "per_request_explicit", resolved.experience.safety.fetch(:provider_spend)
    assert_equal "human_controlled", resolved.experience.safety.fetch(:chat_send)

    patch room_ai_writing_preference_path(@room), params: {preference: {
      profile_id: "development", writing_style: "technical_summary",
      language: "en", tone: "technical"
    }}, as: :json
    assert_response :success
    resolved = AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room)
    assert_equal "room", resolved.source
    assert_equal "en", resolved.effective.fetch(:language)

    patch account_ai_writing_preference_path,
      params: {preference: options(profile: "personal", style: "friendly", language: "es", tone: "warm")}, as: :json
    assert_response :success
    assert_equal "en", AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room).effective.fetch(:language)
    delete room_ai_writing_preference_path(@room), as: :json
    assert_response :success
    assert_equal "account", AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room).source
    assert_equal "es", AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room).effective.fetch(:language)
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
  end

  test "delete defaults falls back to system but retains unrelated member room overrides" do
    sign_in @alice
    patch account_ai_writing_preference_path, params: {preference: options}, as: :json
    assert_response :success
    delete account_ai_writing_preference_path, as: :json
    assert_response :success
    assert_nil AiAccountWritingPreference.find_by(user: @alice)
    assert_equal "system", AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room).source
    assert_equal "neutral", AiWorkspace::WritingPreferenceResolver.for(user: @alice, room: @room).effective.fetch(:tone)
  end

  test "room reset is inaccessible to outsiders and revoked participants" do
    sign_in @alice
    patch room_ai_writing_preference_path(@room), params: {preference: options}, as: :json
    assert_response :success
    outsider = User.create!(email: "account-writer-outsider@example.test",
      password: "test-password-123")
    sign_out @alice
    sign_in outsider
    delete room_ai_writing_preference_path(@room), as: :json
    assert_response :forbidden
    assert_equal 1, AiRoomWritingPreference.count
    sign_out outsider
    @room.participants.where(user: @alice).delete_all
    sign_in @alice
    delete room_ai_writing_preference_path(@room), as: :json
    assert_response :forbidden
    assert_equal 1, AiRoomWritingPreference.count
  end
end
