require "test_helper"

class RoomAiContextMessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @path = room_ai_context_messages_path(@room)
  end

  def grant_all
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
  end

  test "shows a paginated full-room chat inventory only after unanimous grant" do
    grant_all
    first = @room.messages.create!(user: @bob, body: "Project planning milestone alpha")
    second = @room.messages.create!(user: @alice, body: "Discuss budget and dates")
    secret = @room.messages.create!(user: @bob, body: "My password is sk-proj-1234567890123456789")
    sign_in @alice

    post @path, as: :json
    assert_response :success
    payload = response.parsed_body
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "local_review_only", payload.fetch("state")
    assert_equal false, payload.fetch("model_receives_full_history")
    assert_equal 2, payload.fetch("eligible_total")
    assert_equal 1, payload.fetch("excluded_total")
    assert_equal [second.id, first.id], payload.fetch("messages").map { |row| row.fetch("id") }
    assert_equal true, payload.fetch("messages").last.fetch("incoming")
    assert_not_includes response.body, secret.body

    post @path, params: {q: "MILESTONE", author_id: @bob.id}, as: :json
    assert_response :success
    assert_equal [first.id], response.parsed_body.fetch("messages").map { |row| row.fetch("id") }
    post @path, params: {author_id: 123456}, as: :json
    assert_response :unprocessable_entity
  end

  test "rejects missing consent, outsiders, bad dates and public rooms" do
    @room.messages.create!(user: @bob, body: "Private text")
    sign_in @alice
    post @path, as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, "Private text"

    grant_all
    post @path, params: {from: "2026-02-30"}, as: :json
    assert_response :unprocessable_entity
    post @path, params: {page: "0"}, as: :json
    assert_response :unprocessable_entity
    sign_out @alice
    post @path, as: :json
    assert_response :unauthorized

    outsider = User.create!(email: "context-studio-outsider@example.test",
      password: "secure-password-123")
    sign_in outsider
    post @path, as: :json
    assert_response :forbidden

    sign_out outsider
    sign_in @alice
    public_room = Room.create!(name: "Public context not eligible")
    public_room.joinables.create!(user: @alice)
    post room_ai_context_messages_path(public_room), as: :json
    assert_response :forbidden
  end

  test "revoked grant immediately closes the inventory" do
    grant_all
    @room.messages.create!(user: @bob, body: "Revoke-sensitive source")
    sign_in @alice
    post @path, as: :json
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post @path, as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, "Revoke-sensitive source"
  end
end
