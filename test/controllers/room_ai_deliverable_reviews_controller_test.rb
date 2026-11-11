require "test_helper"

class RoomAiDeliverableReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Checkout returns HTTP 422. Please inspect the Rails validation errors.")
    @text = "## Requirements\n- Investigate checkout HTTP 422 [M#{@incoming.id}]\n" \
      "## Open Questions\n- Deadline needs confirmation"
    sign_in @alice
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "requires room-wide opt-in even for offline GET and POST" do
    get new_room_ai_deliverable_review_path(@room)
    assert_response :forbidden
    grant_all
    get new_room_ai_deliverable_review_path(@room)
    assert_response :success
    assert_select "h1", /Structured deliverable review/
    assert_equal "private, no-store", response.headers["Cache-Control"]
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief", text: @text } }
    assert_response :forbidden
    assert_not_includes response.body, "Checkout returns"
  end

  test "offline parse shows escaped entries and authorized source links without writes" do
    grant_all
    count = Message.count
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief", text: @text } }
    assert_response :success
    assert_select "#h4-typed-results li", 2
    assert_select "#h4-typed-results a[href=?]",
      room_path(@room, focus: @incoming.id), count: 1
    assert_select "#h4-typed-results", /Pending manual review/
    assert_equal count, Message.count
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "manual designation requires explicit POST and is not Send or approval" do
    grant_all
    count = Message.count
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        decisions: { "1" => "confirm", "2" => "request_confirmation" } }
    }
    assert_response :success
    assert_select "#h4-typed-results", /Reviewed not approved/
    assert_select "#h4-typed-results", /Confirmed/
    assert_equal count, Message.count
  end

  test "foreign source id and malformed decision fail closed" do
    grant_all
    other = Room.create!(name: "Foreign private", kind: "private_group",
      is_private: true, owner: @bob)
    other.participants.create!(user: @bob, group_role: "owner")
    foreign = other.messages.create!(user: @bob, body: "Secret foreign content")
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief",
        text: "## Requirements\n- Leak [M#{foreign.id}]" } }
    assert_response :unprocessable_entity
    assert_not_includes response.body, "Secret foreign content"

    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        decisions: { "999" => "confirm" } }
    }
    assert_response :unprocessable_entity
    assert_not_includes response.body, @text
  end

  test "escaped input is not executable HTML" do
    grant_all
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief",
        text: "## Requirements\n- <script>alert(1)</script> [M#{@incoming.id}]" }
    }
    assert_response :success
    assert_select "#h4-typed-results script", count: 0
    assert_includes response.body, "&lt;script&gt;"
  end

  test "departed or unauthenticated user cannot view review" do
    grant_all
    sign_out @alice
    get new_room_ai_deliverable_review_path(@room)
    assert_response :redirect
    sign_in @alice
    @room.participants.where(user: @alice).delete_all
    get new_room_ai_deliverable_review_path(@room)
    assert_response :forbidden
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief", text: @text } }
    assert_response :forbidden
  end
end
