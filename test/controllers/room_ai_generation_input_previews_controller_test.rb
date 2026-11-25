require "test_helper"

class RoomAiGenerationInputPreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_generation_input_preview_path(@room)
    @incoming = @room.messages.create!(user: @bob,
      body: "Which Rails signup form needs improvement?")
    AiConversationGoal.create!(room: @room, user: @alice,
      purpose: "Clarify project requirements", revision: 1, active: true)
  end

  def grant_context
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "only authenticated eligible members can obtain a preview" do
    post @url, params: { preview: { mode: "answer", draft_text: "",
      expected_goal_revision: 1 } }, as: :json
    assert_response :unauthorized
    sign_in @alice
    post room_ai_generation_input_preview_path(99_999_999),
      params: { preview: { mode: "beautify", draft_text: "Fix Rails." } }, as: :json
    assert_response :not_found
  end

  test "answer preview requires eligible incoming source and current goal, never dispatches provider or Send" do
    sign_in @alice
    payload = { preview: { mode: "answer", draft_text: "",
      expected_goal_revision: 1 } }
    post @url, params: payload, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_or_stale_input", response.parsed_body.fetch("error")
    grant_context
    post @url, params: payload, as: :json
    assert_response :success
    result = response.parsed_body
    assert_equal "answer", result.fetch("mode")
    assert_equal [@incoming.id], result.fetch("source_ids")
    assert_equal "Clarify project requirements", result.fetch("goal_purpose")
    assert_equal "Which Rails signup form needs improvement?",
      result.fetch("sources").sole.fetch("text")
    effective = result.fetch("effective_plan")
    assert_equal "suggest_reply_for_human_review", effective.fetch("task")
    assert_equal "bounded_room_context", effective.dig("context", "policy")
    assert_equal "M#{@incoming.id}", effective.dig("context", "reply_to_ref")
    assert_equal false, effective.dig("context", "full_history_covered")
    assert_equal 1, effective.dig("context", "included")
    assert_equal "0.100000", effective.fetch("on_paid_request_reservation_usd")
    assert_nil effective.fetch("estimated_cost_usd")
    assert_equal false, effective.fetch("provider_called")
    assert_equal false, effective.fetch("budget_reserved")
    assert_equal true, effective.fetch("separate_manual_send_required")
    assert_equal false, result.fetch("provider_called")
    assert_equal false, result.fetch("budget_reserved")
    assert_equal false, result.fetch("message_sent")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal 1, @room.messages.count

    AiConversationGoal.find_by!(room: @room, user: @alice).update!(revision: 2)
    post @url, params: payload, as: :json
    assert_response :unprocessable_entity
  end

  test "signed source controls actually recompile the chosen incoming reply target" do
    sign_in @alice
    grant_context
    newer = @room.messages.create!(user: @bob,
      body: "Can you send the landing page materials?")
    own = @room.messages.create!(user: @alice,
      body: "The design requirements are being reviewed.")
    base = { mode: "answer", draft_text: "", expected_goal_revision: 1 }
    post @url, params: { preview: base }, as: :json
    assert_response :success
    original = response.parsed_body
    assert_equal "M#{newer.id}", original.dig("effective_plan", "context", "reply_to_ref")
    token = original.fetch("source_token")
    assert token.is_a?(String)
    assert token.length > 30

    post @url, params: { preview: base.merge(source_token: token,
      selected_ids: [@incoming.id, own.id], reply_target_id: @incoming.id) }, as: :json
    assert_response :success
    chosen = response.parsed_body
    assert_equal [@incoming.id, own.id], chosen.fetch("source_ids")
    assert_equal "M#{@incoming.id}", chosen.dig("effective_plan", "context", "reply_to_ref")
    assert_equal false, chosen.fetch("provider_called")
    assert_equal 0, AiUsageReservation.count

    post @url, params: { preview: base.merge(source_token: token,
      selected_ids: [@incoming.id, own.id], reply_target_id: own.id) }, as: :json
    assert_response :unprocessable_entity
    assert_equal 3, @room.messages.count
  end

  test "beautify preview contains only author draft without peer consent or spending" do
    sign_in @alice
    post @url, params: { preview: { mode: "beautify",
      draft_text: "pls fix ruby on rails bug." } }, as: :json
    assert_response :success
    result = response.parsed_body
    assert_equal "beautify", result.fetch("mode")
    assert_equal "pls fix ruby on rails bug.", result.fetch("draft_preview")
    assert_equal [], result.fetch("sources")
    assert_equal "beautify_own_unsent_draft", result.dig("effective_plan", "task")
    assert_equal "own_draft_only", result.dig("effective_plan", "context", "policy")
    assert_equal 0, result.dig("effective_plan", "context", "included")
    assert_equal "system", result.dig("effective_plan", "preference_origin")

    assert_not_includes response.body, @incoming.body
    assert_equal 1, @room.messages.count
  end

  test "Beautify preflight reflects explicit one-shot preset and tone, with no provider spending" do
    sign_in @alice
    post @url, params: { preview: { mode: "beautify",
      draft_text: "Please check the Rails scope.",
      preset_id: "professional_client_reply",
      writing_language: "ru", writing_tone: "formal" } }, as: :json
    # Unsupported one-shot settings must never silently downgrade to defaults.
    assert_response :unprocessable_entity

    post @url, params: { preview: { mode: "beautify",
      draft_text: "Please check the Rails scope.",
      preset_id: "professional_client_reply",
      writing_language: "ru", writing_tone: "commercial" } }, as: :json
    assert_response :unprocessable_entity

    post @url, params: { preview: { mode: "beautify",
      draft_text: "Please check the Rails scope.",
      preset_id: "professional_client_reply",
      writing_language: "ru", writing_tone: "neutral" } }, as: :json
    assert_response :success
    effective = response.parsed_body.fetch("effective_plan")
    assert_equal "professional_client_reply", effective.dig("one_shot_options", "preset_id")
    assert_equal "ru", effective.dig("one_shot_options", "writing_language")
    assert_equal "neutral", effective.dig("one_shot_options", "writing_tone")
    assert_equal [], response.parsed_body.fetch("source_ids")
    assert_equal false, effective.fetch("provider_called")
    assert_equal 0, AiUsageReservation.count
    assert_equal 1, @room.messages.count
  end

  test "tampered payload, nonempty answer and missing draft are denied" do
    sign_in @alice
    grant_context
    [
      { mode: "auto_reply", draft_text: "" },
      { mode: "answer", draft_text: "Do not replace my draft", expected_goal_revision: 1 },
      { mode: "beautify", draft_text: "" },
      { mode: "beautify", draft_text: "hi", provider: "xai" },
      { mode: "answer", draft_text: "", expected_goal_revision: 999 }
    ].each do |bad|
      post @url, params: { preview: bad }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 1, @room.messages.count
  end
end
