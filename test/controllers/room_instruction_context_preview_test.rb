require "test_helper"

class RoomInstructionContextPreviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "What is the expected Rails scope?")
    @room.ai_instruction_revisions.create!(editor: @bob,
      revision_number: 1, content: "Keep responses factual. Price not confirmed.")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "default local preview omits room instructions, opt-in includes exact revision" do
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post preview_room_ai_context_path(@room), params: {preview: {hint: ""}}, as: :json
      assert_response :success
      assert_equal false, response.parsed_body.fetch("room_instruction_included")
      assert_nil response.parsed_body.fetch("room_instruction")

      post preview_room_ai_context_path(@room), params: {
        preview: {hint: "", include_room_instructions: "1"}
      }, as: :json
      assert_response :success
      data = response.parsed_body
      assert_equal true, data.fetch("room_instruction_included")
      assert_equal 1, data.dig("room_instruction", "revision_number")
      assert_equal "Keep responses factual. Price not confirmed.",
        data.dig("room_instruction", "text")
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_kind_of String, data.fetch("source_token")
      assert_no_difference "Message.count" do
        get room_ai_instructions_path(@room), as: :json
      end
    end
  end

  test "unauthorized/revoked member and invalid opt-in never receive instruction preview" do
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post preview_room_ai_context_path(@room),
        params: {preview: {include_room_instructions: "true"}}, as: :json
      assert_response :unprocessable_entity

      AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
      post preview_room_ai_context_path(@room),
        params: {preview: {include_room_instructions: "1"}}, as: :json
      assert_response :unprocessable_entity
      assert_not_includes response.body, "Keep responses factual"

      AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob).grant!
      @room.participants.where(user: @alice).delete_all
      post preview_room_ai_context_path(@room),
        params: {preview: {include_room_instructions: "1"}}, as: :json
      assert_response :forbidden
    end
  end
end
