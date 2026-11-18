require "test_helper"

class RoomAiAutomationPreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @path = preview_room_ai_automation_summary_path(@room)
    @message = @room.messages.create!(user: @bob,
      body: "We need to investigate the Rails registration failure.")
  end

  def grant_all
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
  end

  def preview(kind)
    post @path, params: {preview: {kind: kind}}, as: :json
  end

  test "consented summary is deterministic and makes no provider call, send or saved document" do
    sign_in @alice
    grant_all
    preview "conversation_summary"
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    data = response.parsed_body
    assert_equal "conversation_summary", data.fetch("kind")
    assert_equal false, data.fetch("provider_called")
    assert_equal false, data.fetch("saved")
    assert_equal false, data.fetch("context_complete")
    assert_equal true, data.fetch("requires_human_review")
    assert_equal [@message.id], data.fetch("source_message_ids")
    assert_includes data.fetch("text"), "[M#{@message.id}]"
    assert_includes data.fetch("text"), "To confirm"
    assert_equal 1, @room.messages.count
    assert_equal 0, AiDeliverable.count
    assert_equal 0, AiAutomationPolicy.count
  end

  test "already implemented client brief can be generated without duplicating H4" do
    sign_in @alice
    grant_all
    preview "client_brief"
    assert_response :success
    assert_equal "client_brief", response.parsed_body.fetch("kind")
    assert_includes response.parsed_body.fetch("text"), "## Objective"
    assert_includes response.parsed_body.fetch("text"), "[M#{@message.id}]"
    assert_equal false, response.parsed_body.fetch("provider_called")
    assert_equal 0, AiDeliverable.count
  end

  test "invalid kinds and extra fields cannot sneak into context or provider" do
    sign_in @alice
    grant_all
    preview "open_questions"
    assert_response :unprocessable_entity
    post @path, params: {preview: {kind: "conversation_summary",
      send_auto: true}}, as: :json
    assert_response :unprocessable_entity
    post @path, params: {preview: {kind: ["conversation_summary"]}}, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, AiDeliverable.count
    assert_equal 1, @room.messages.count
  end

  test "no consent, nonmember and departed authors deny private extracts" do
    sign_in @alice
    preview "conversation_summary"
    assert_response :unprocessable_entity
    assert_not_includes response.body, @message.body

    grant_all
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    preview "conversation_summary"
    assert_response :unprocessable_entity
    assert_not_includes response.body, @message.body

    sign_out @alice
    outsider = User.create!(email: "automation-preview-outsider@example.test",
      password: "test-password-123")
    sign_in outsider
    preview "conversation_summary"
    assert_response :forbidden

    sign_out outsider
    sign_in @alice
    grant_all
    @room.participants.where(user: @bob).delete_all
    preview "conversation_summary"
    assert_response :unprocessable_entity
    assert_not_includes response.body, @message.body
  end
end
