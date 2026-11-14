require "test_helper"

# Preserves the true authorization status while providing safe HTML for
# browser navigation. APIs, Turbo streams and private files remain unchanged.
class UiErrorStatesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @message = @room.messages.create!(user: @bob, body: "PRIVATE_NOTE_DO_NOT_RENDER")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    sign_in @alice
  end

  test "revoked AI consent shows branded 403 without document or private message" do
    post room_ai_deliverables_path(@room), params: { deliverable: {
      kind: "client_brief",
      text: "## Requirements\n- PRIVATE_NOTE_DO_NOT_RENDER [M#{@message.id}]"
    } }
    assert_response :redirect
    item = AiDeliverable.last

    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get room_ai_deliverable_path(@room, item)
    assert_response :forbidden
    assert_equal "ai_consent_paused", response.headers["X-Relay-Error-State"]
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "#sd-ui-error-fallback h1", text: "AI access paused"
    assert_select "a[href=?]", rooms_path
    assert_select "dialog.sd-ui-error-dialog", count: 1
    assert_not_includes response.body, "PRIVATE_NOTE_DO_NOT_RENDER"
  end

  test "unavailable room uses branded 403 but does not reveal its name" do
    outsider = User.create!(email: "outsider-#{SecureRandom.hex(4)}@example.test",
      password: "TestPassword123!")
    sign_out @alice
    sign_in outsider
    get room_path(@room)
    assert_response :forbidden
    assert_equal "room_access_unavailable", response.headers["X-Relay-Error-State"]
    assert_select "#sd-ui-error-fallback", text: /Conversation unavailable/
    assert_not_includes response.body, @room.name
    assert_not_includes response.body, @message.body
  end

  test "missing room gives a branded 404 response" do
    get room_path(99_999_991)
    assert_response :not_found
    assert_equal "http_404", response.headers["X-Relay-Error-State"]
    assert_select "#sd-ui-error-fallback h1", text: "Content unavailable"
  end

  test "JSON and Turbo Stream errors keep original machine formats" do
    post room_ai_deliverables_path(@room),
      params: { deliverable: { kind: "client_brief", text: "no source" } },
      as: :json
    assert_response :unprocessable_entity
    assert_nil response.headers["X-Relay-Error-State"]
    assert_not_includes response.body, "sd-ui-error-fallback"

    post room_message_reactions_path(@room, @message),
      params: { reaction: { emoji: "invalid" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_nil response.headers["X-Relay-Error-State"]
    assert_not_includes response.body, "sd-ui-error-fallback"
  end

  test "attachment and avatar error responses remain raw" do
    get chat_attachment_path(99_999_991)
    assert_response :not_found
    assert_nil response.headers["X-Relay-Error-State"]
    assert_not_includes response.body, "sd-ui-error-fallback"

    get user_avatar_path(99_999_991)
    assert_response :not_found
    assert_nil response.headers["X-Relay-Error-State"]
  end
end
