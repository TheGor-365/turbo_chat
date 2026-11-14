require "test_helper"
require "minitest/mock"

class RoomAiDraftsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def params_for
    { draft: { text: "Safe dummy text.", preset_id: "polish_clarity",
      consent: "1", request_id: SecureRandom.uuid } }
  end

  test "no secret or switch means no generated text even for an authorized member" do
    sign_in @alice
    assert_no_difference "Message.count" do
      post generate_room_ai_draft_path(@room), params: params_for
    end
    assert_response :service_unavailable
    assert_equal "no-store", response.headers["Cache-Control"].split(", ").last
    assert_not_includes response.body, "Safe dummy text."
    get room_path(@room)
    assert_select ".sd-ai-manual-generate", count: 0
  end

  test "guest and nonmember cannot generate or see another room" do
    post generate_room_ai_draft_path(@room), params: params_for
    assert_redirected_to new_user_session_path

    outsider = User.create!(email: "h3c-outsider@example.test", password: "secure-password-123")
    sign_in outsider
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      post generate_room_ai_draft_path(@room), params: params_for
      assert_response :forbidden
      assert_not_includes response.body, "Safe dummy text."
    end
  end

  test "translate cannot bypass the explicit language selection" do
    sign_in @alice
    original = Message.count
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      post generate_room_ai_draft_path(@room), params: {
        draft: params_for.fetch(:draft).merge(preset_id: "translate_preserving_tone")
      }
    end
    assert_response :unprocessable_entity
    assert_equal original, Message.count
    assert_not_includes response.body, "Safe dummy text."
  end

  test "manual enabled state reveals only opt-in UI and never silently posts a message" do
    sign_in @alice
    AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
      get room_path(@room)
      assert_response :success
      assert_select ".sd-ai-manual-generate input[type=checkbox]", count: 0
      assert_select ".sd-ai-manual-generate button[data-action='click->ai-draft#generate'][disabled]", count: 1
      assert_select ".sd-ai-manual-generate .sd-ai-consent-note", count: 0
      assert_select ".sd-ai-provider-details", /Clicking a Grok button approves one paid request/
      assert_select "form.message-composer", count: 1
    end
  end
end
