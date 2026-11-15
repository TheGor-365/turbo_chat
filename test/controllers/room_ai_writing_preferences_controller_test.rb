require "test_helper"

class RoomAiWritingPreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def preference(profile_id: "business", writing_style: "professional_client_reply",
    language: "ru", tone: "professional")
    { profile_id: profile_id, writing_style: writing_style,
      language: language, tone: tone }
  end

  test "member settings persist per user per room without affecting peers" do
    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_redirected_to new_user_session_path

    sign_in @alice
    get room_ai_writing_preference_path(@room)
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_nil response.parsed_body.fetch("preference")

    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal preference.stringify_keys, response.parsed_body.fetch("preference")
    assert_equal "professional_client_reply",
      AiRoomWritingPreference.find_by!(user: @alice, room: @room).experience.settings.fetch(:writing_style)
    assert_equal 1, AiRoomWritingPreference.count
    sign_out @alice

    sign_in @bob
    get room_ai_writing_preference_path(@room)
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    patch room_ai_writing_preference_path(@room), params: {
      preference: preference(profile_id: "development",
        writing_style: "technical_summary", language: "en", tone: "technical"),
      user_id: @alice.id
    }
    assert_response :success
    assert_equal 2, AiRoomWritingPreference.count
    assert_equal "professional_client_reply",
      AiRoomWritingPreference.find_by!(user: @alice, room: @room).writing_style
    assert_equal "technical_summary",
      AiRoomWritingPreference.find_by!(user: @bob, room: @room).writing_style
  end

  test "invalid payload and attempted privilege changes fail without mutation" do
    sign_in @alice
    invalid = [
      preference.merge(allow_auto_send: true),
      preference.merge(writing_style: "malicious_system_prompt"),
      preference.merge(profile_id: "admin"),
      preference.merge(language: "xx"),
      preference.merge(tone: "authorize_paid_requests"),
      preference.merge(writing_style: "friendly"),
      { writing_style: "polish_clarity" }
    ]
    invalid.each do |payload|
      patch room_ai_writing_preference_path(@room), params: { preference: payload }
      assert_response :unprocessable_entity
      assert_equal 0, AiRoomWritingPreference.count
    end

    patch room_ai_writing_preference_path(@room), params: {
      preference: preference(profile_id: nil, writing_style: "friendly", tone: "warm")
    }, as: :json
    assert_response :success
    assert_nil AiRoomWritingPreference.last.profile_id
    assert_equal "friendly", AiRoomWritingPreference.last.writing_style
    assert_equal "human_controlled", AiRoomWritingPreference.last.experience.safety[:chat_send]
    assert_equal "per_request_explicit", AiRoomWritingPreference.last.experience.safety[:provider_spend]
  end

  test "outsiders, revoked members and unrelated rooms cannot access settings" do
    outsider = User.create!(email: "writing-outsider@example.test",
      password: "test-password-123")
    sign_in outsider
    get room_ai_writing_preference_path(@room)
    assert_response :forbidden
    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_response :forbidden
    assert_equal 0, AiRoomWritingPreference.count

    sign_out outsider
    sign_in @alice
    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_response :success
    @room.participants.where(user: @alice).delete_all
    get room_ai_writing_preference_path(@room)
    assert_response :forbidden
    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_response :forbidden
    assert_equal 1, AiRoomWritingPreference.count

    get room_ai_writing_preference_path("999999999")
    assert_response :not_found
  end

  test "same member settings in two rooms remain isolated" do
    another = Room.create!(name: "Other preferences room", is_private: false, kind: "public_room")
    another.joinables.create!(user: @alice)
    sign_in @alice
    patch room_ai_writing_preference_path(@room), params: { preference: preference }
    assert_response :success
    patch room_ai_writing_preference_path(another), params: {
      preference: preference(profile_id: "personal", writing_style: "friendly",
        tone: "warm", language: "es")
    }
    assert_response :success
    assert_equal 2, AiRoomWritingPreference.where(user: @alice).count
    assert_equal "ru", AiRoomWritingPreference.find_by!(user: @alice, room: @room).language
    assert_equal "es", AiRoomWritingPreference.find_by!(user: @alice, room: another).language
  end
  test "rapid valid changes stay member-scoped and do not alter provider permissions" do
    sign_in @alice
    states = [
      preference(profile_id: "development", writing_style: "technical_summary",
        language: "auto", tone: "technical"),
      preference(profile_id: "development", writing_style: "technical_summary",
        language: "ru", tone: "technical"),
      preference(profile_id: nil, writing_style: "technical_summary",
        language: "ru", tone: "warm")
    ]
    states.each do |state|
      patch room_ai_writing_preference_path(@room), params: { preference: state }, as: :json
      assert_response :success
    end
    item = AiRoomWritingPreference.find_by!(user: @alice, room: @room)
    assert_equal states.last.stringify_keys, item.public_snapshot.stringify_keys
    assert_equal 1, AiRoomWritingPreference.where(user: @alice, room: @room).count
    assert_equal "per_request_explicit", item.experience.safety[:provider_spend]
    assert_equal "human_controlled", item.experience.safety[:chat_send]
    assert_equal 0, @room.messages.count
  end

end
