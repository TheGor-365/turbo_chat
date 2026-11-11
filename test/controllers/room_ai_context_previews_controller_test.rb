require "test_helper"

class RoomAiContextPreviewsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "The Rails PostgreSQL client proposal requires review.")
  end

  def grant(user)
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
  end

  test "only explicit request returns bounded in-room sources and reasons without generation" do
    grant(@alice)
    grant(@bob)
    @room.messages.create!(user: @bob, body: "unsafe@example.test must not be returned")
    before = Message.count
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post preview_room_ai_context_path(@room),
        params: { preview: { hint: "Clarify the client proposal scope." } }
    end
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    payload = JSON.parse(response.body)
    assert_equal 2, payload.fetch("retrieval_version")
    assert_match(/recalculated/, payload.fetch("disclaimer"))
    sources = payload.fetch("sources")
    assert sources.any?
    assert_operator sources.size, :<=, 9
    assert_operator sources.sum { |s| s.fetch("text").length }, :<=, 2_400
    entry = sources.find { |s| s.fetch("id") == @incoming.id }
    assert_equal "latest_incoming", entry.fetch("reason")
    assert_equal room_path(@room, focus: @incoming.id), entry.fetch("url")
    assert sources.all? { |s| %w[latest_incoming recent_turn keyword_match context_fallback].include?(s.fetch("reason")) }
    assert_not_includes response.body, "unsafe@example.test"
    assert_equal before, Message.count
  end

  test "blocked if not every current member consents, and on revoke" do
    grant(@alice)
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post preview_room_ai_context_path(@room), params: { preview: { hint: "" } }
      assert_response :unprocessable_entity
      grant(@bob)
      post preview_room_ai_context_path(@room), params: { preview: { hint: "" } }
      assert_response :success
      AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
      post preview_room_ai_context_path(@room), params: { preview: { hint: "" } }
      assert_response :unprocessable_entity
    end
  end

  test "rejects outsider and departed member without returning content" do
    grant(@alice)
    grant(@bob)
    outsider = User.create!(email: "preview-outsider@example.test",
      password: "safe-password-123")
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      sign_in outsider
      post preview_room_ai_context_path(@room), params: { preview: { hint: "Rails" } }
      assert_response :forbidden
      sign_in @alice
      @room.participants.where(user: @alice).delete_all
      post preview_room_ai_context_path(@room), params: { preview: { hint: "Rails" } }
      assert_response :forbidden
    end
    assert_not_includes response.body, @incoming.body
  end

  test "rejects private data in author hint without echoing it" do
    grant(@alice)
    grant(@bob)
    sign_in @alice
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      post preview_room_ai_context_path(@room),
        params: { preview: { hint: "Send to unsafe@example.test" } }
    end
    assert_response :unprocessable_entity
    assert_not_includes response.body, "unsafe@example.test"
  end
end
