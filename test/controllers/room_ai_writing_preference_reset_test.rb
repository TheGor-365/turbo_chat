require "test_helper"

class RoomAiWritingPreferenceResetTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner, @member = users(:one), users(:two)
    @room = Room.create!(name: "Personal reset contract", kind: "private_group",
      is_private: true, owner: @owner)
    @room.participants.create!(user: @owner, group_role: "owner")
    @room.participants.create!(user: @member, group_role: "member")
    @path = room_ai_writing_preference_path(@room)
  end

  def preference(language: "ru")
    { profile_id: "universal", writing_style: "polish_clarity",
      language: language, tone: "neutral" }
  end

  test "reset inherits current shared defaults and reflects later owner edits" do
    AiAccountWritingPreference.create!(user: @member, **preference(language: "es"))
    AiWorkspace::SharedWritingPreferences.write(room: @room, actor: @owner,
      attributes: preference(language: "en"), expected_revision: 0)
    AiRoomWritingPreference.create!(user: @member, room: @room, **preference)
    sign_in @member

    assert_no_difference ["AiRoomSharedWritingPreference.count",
      "AiAccountWritingPreference.count", "AiUsageReservation.count",
      "AiRoomContextConsent.count", "Message.count"] do
      delete @path
      assert_response :success
    end
    body = response.parsed_body
    assert_equal false, body.fetch("configured")
    assert_equal "shared", body.fetch("source")
    assert_equal preference(language: "en").stringify_keys, body.fetch("preference")
    assert_equal 1, body.fetch("shared_revision")
    assert_nil AiRoomWritingPreference.find_by(room: @room, user: @member)

    get room_path(@room)
    assert_response :success
    node = css_select("[data-ai-draft-effective-preference]").first
    assert node, "room composer must expose effective server preferences"
    assert_equal "shared", node["data-ai-draft-preference-source"]
    assert_equal "en", JSON.parse(node["data-ai-draft-effective-preference"]).fetch("language")

    AiWorkspace::SharedWritingPreferences.write(room: @room, actor: @owner,
      attributes: preference(language: "hy"), expected_revision: 1)
    delete @path
    assert_response :success
    assert_equal "shared", response.parsed_body.fetch("source")
    assert_equal "hy", response.parsed_body.dig("preference", "language")
    assert_equal 2, response.parsed_body.fetch("shared_revision")
    assert_equal "es", AiAccountWritingPreference.find_by!(user: @member).language
  end

  test "without shared defaults repeated reset inherits account then system" do
    AiAccountWritingPreference.create!(user: @member, **preference(language: "es"))
    AiRoomWritingPreference.create!(user: @member, room: @room, **preference)
    sign_in @member
    2.times do
      delete @path
      assert_response :success
      assert_equal "account", response.parsed_body.fetch("source")
      assert_equal "es", response.parsed_body.dig("preference", "language")
      assert_equal 0, response.parsed_body.fetch("shared_revision")
    end
    assert_nil AiRoomWritingPreference.find_by(room: @room, user: @member)
    AiAccountWritingPreference.where(user: @member).delete_all
    delete @path
    assert_response :success
    assert_equal "system", response.parsed_body.fetch("source")
    assert_equal "auto", response.parsed_body.dig("preference", "language")
    assert_equal "universal", response.parsed_body.dig("preference", "profile_id")
  end

  test "personal reset cannot mutate the owner's override or history grant" do
    AiRoomWritingPreference.create!(user: @owner, room: @room, **preference(language: "en"))
    AiRoomWritingPreference.create!(user: @member, room: @room, **preference)
    grant = AiRoomContextConsent.find_or_initialize_by(room: @room, user: @owner)
    grant.grant!
    sign_in @member
    assert_no_difference ["AiRoomContextConsent.count", "AiUsageReservation.count",
      "Message.count"] do
      delete @path, params: { user_id: @owner.id }
      assert_response :success
    end
    assert_equal "en", AiRoomWritingPreference.find_by!(user: @owner, room: @room).language
    assert AiRoomContextConsent.find_by!(user: @owner, room: @room).enabled?
    assert_nil AiRoomWritingPreference.find_by(user: @member, room: @room)
  end

  test "guest outsider and departed member cannot reset protected preferences" do
    AiRoomWritingPreference.create!(user: @member, room: @room, **preference)
    delete @path
    assert_redirected_to new_user_session_path
    outsider = User.create!(email: "reset-outsider@example.test", password: "password123")
    sign_in outsider
    delete @path
    assert_response :forbidden
    sign_out outsider
    sign_in @member
    @room.participants.where(user: @member).delete_all
    delete @path
    assert_response :forbidden
    assert AiRoomWritingPreference.exists?(user: @member, room: @room)
    assert_equal 0, AiUsageReservation.count
  end
  test "effective read resolves current shared revision and preserves personal override without writes" do
    shared = preference(language: "en")
    AiWorkspace::SharedWritingPreferences.write(room: @room, actor: @owner,
      attributes: shared, expected_revision: 0)
    sign_in @member
    path = room_ai_effective_writing_preference_path(@room)
    assert_no_difference ["AiRoomWritingPreference.count", "AiRoomSharedWritingPreference.count",
      "AiUsageReservation.count", "Message.count", "AiRoomContextConsent.count"] do
      get path, as: :json
      assert_response :success
    end
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "shared", response.parsed_body.fetch("source")
    assert_equal 1, response.parsed_body.fetch("shared_revision")
    assert_equal "en", response.parsed_body.dig("preference", "language")
    AiRoomWritingPreference.create!(user: @member, room: @room, **preference(language: "es"))
    AiWorkspace::SharedWritingPreferences.write(room: @room, actor: @owner,
      attributes: shared.merge(language: "hy"), expected_revision: 1)
    get path, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("configured")
    assert_equal "room", response.parsed_body.fetch("source")
    assert_equal 2, response.parsed_body.fetch("shared_revision")
    assert_equal "es", response.parsed_body.dig("preference", "language")
    @room.participants.where(user: @member).delete_all
    get path, as: :json
    assert_response :forbidden
  end
  test "personal OFF removes generation endpoints even when runtime flags allow generation" do
    AiWorkspace::PersonalEnablement.write(actor: @member, enabled: false, expected_revision: 0)
    sign_in @member
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
        AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
          AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
            get room_path(@room)
            assert_response :success
            assert_select "[data-personal-ai-enabled='false']", count: 1
            assert_select "[data-personal-ai-off-notice]", count: 1
            assert_select "[data-quick-beautify-target='generate'][disabled]", count: 1
            assert_select "[data-ai-answer-entry-target='trigger'][disabled]", count: 1
            %w[data-quick-beautify-url data-ai-draft-generate-url data-ai-answer-entry-generate-url-value data-ai-draft-context-reply-url data-ai-draft-context-task-url].each do |attribute|
              assert_select "[#{attribute}]", count: 0
            end
            assert_select "button.composer-send", count: 1
          end
        end
      end
    end
    assert_equal 0, AiUsageReservation.count
    assert_equal 0, @room.messages.count
    assert_nil AiPersonalEnablement.find_by(user: @owner)
  end
end
