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
    assert_select "h1", /Review a client document/
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

  test "H4 is discoverable via icons from the conversation and AI Workspace" do
    grant_all
    get room_path(@room)
    assert_response :success
    assert_select "a.sd-ai-entry[href=?][title=?]",
      room_ai_workspace_path(@room), "AI Workspace · select context and review locally", count: 1
    assert_select "a.sd-h4-entry[href=?][aria-label=?]",
      new_room_ai_deliverable_review_path(@room), "Open manual document review", count: 1

    # The contextual composer is rendered according to independent feature flags.
    # Check the room-level H4 navigation regardless of Grok availability.
    assert_select "a.sd-h4-entry[href=?]",
      new_room_ai_deliverable_review_path(@room), count: 1
    get room_ai_workspace_path(@room)
    assert_response :success
    assert_select "a.sd-ai-tool-link[href=?]",
      new_room_ai_deliverable_review_path(@room), count: 1
    assert_select "a.sd-ai-tool-link .sd-icon", count: 2

    get new_room_ai_deliverable_review_path(@room)
    assert_response :success
    assert_select "a.sd-activity-back[href=?]", room_ai_workspace_path(@room), count: 1
    assert_select "#deliverable-kind", count: 1
    assert_select ".sd-archive-picker__trigger[aria-haspopup=listbox]", minimum: 1
    assert_select "select[name='deliverable[kind]'] option", count: 3
    assert_select ".sd-h4-markdown", count: 1
    assert_select "button.sd-h4-submit[aria-label='Re-check access and review decisions']", count: 1
  end

  test "handed-off conversation summary is parsed offline only after current consent" do
    grant_all
    summary = "## Summary\n- Checkout returns 422 [M#{@incoming.id}]\n" \
      "## Open Questions\n- Who owns the fix?"
    original = Message.count
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "conversation_summary", text: summary }
    }
    assert_response :success
    assert_select "#h4-typed-results .sd-h4-entry", count: 2
    assert_select "#h4-typed-results .sd-h4-status[data-status=inferred]", count: 1
    assert_select "#h4-typed-results .sd-h4-status[data-status=needs_confirmation]", count: 1
    assert_equal original, Message.count
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "conversation_summary", text: summary }
    }
    assert_response :forbidden
    assert_not_includes response.body, "Checkout returns 422"
  end

  test "automatic room evidence loads on GET with only current authorized sources" do
    grant_all
    count = Message.count
    get new_room_ai_deliverable_review_path(@room)
    assert_response :success
    assert_select "textarea[name='deliverable[text]']", text: /M#{@incoming.id}/
    assert_select "#h4-typed-results .sd-h4-status[data-status=inferred]", minimum: 1
    assert_select "#h4-typed-results a[href=?]",
      room_path(@room, focus: @incoming.id), minimum: 1
    assert_select ".sd-h4-auto-notice", /not an AI-verified summary/
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal count, Message.count
  end

  test "automatic room evidence cannot load after participant revocation" do
    grant_all
    get new_room_ai_deliverable_review_path(@room)
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get new_room_ai_deliverable_review_path(@room)
    assert_response :forbidden
    assert_not_includes response.body, "Checkout returns"
  end

  test "synthetic browser sample loads without generation, persistence or automatic confirmation" do
    grant_all
    original = Message.count
    get new_room_ai_deliverable_review_path(@room, demo: "1")
    assert_response :success
    assert_select "textarea[name='deliverable[text]']", text: /Diagnose an HTTP 422/
    assert_select "a.sd-h4-demo-link[href=?]",
      new_room_ai_deliverable_review_path(@room, demo: "1"), count: 1
    sample = "Client Brief\nObjective\nDiagnose an HTTP 422 validation response\n" \
      "Requirements\n- Inspect Rails model validations\n" \
      "- Review permitted request parameters\n" \
      "Open Questions\n- Deadline: To confirm\n- Budget: To confirm"
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief", text: sample } }
    assert_response :success
    assert_select "#h4-typed-results .sd-h4-entry", count: 5
    assert_select "#h4-typed-results .sd-h4-status[data-status=needs_confirmation]", count: 5
    assert_equal original, Message.count
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "separate proposed revision produces exact diff with no message write" do
    grant_all
    revised = "## Requirements\n- Investigate checkout HTTP 422 [M#{@incoming.id}]\n" \
      "## Open Questions\n- Budget: To confirm"
    before = Message.count
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        revision_text: revised, intent: "compare" }
    }
    assert_response :success
    assert_select "#h4-version-comparison", count: 1
    assert_select "#h4-version-comparison .sd-h4-entry[data-change=unchanged]", count: 1
    assert_select "#h4-version-comparison .sd-h4-entry[data-change=removed]", count: 1
    assert_select "#h4-version-comparison .sd-h4-entry[data-change=added]", count: 1
    assert_select "form.sd-h4-revision-form textarea[name='deliverable[revision_text]']", count: 1
    assert_equal before, Message.count
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "revision comparison rejects forged sources, decisions and stale consent" do
    grant_all
    bad = "## Requirements\n- Foreign [M999999999999]"
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        revision_text: bad, intent: "compare" }
    }
    assert_response :unprocessable_entity
    assert_not_includes response.body, bad

    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        revision_text: @text, intent: "compare", decisions: { "1" => "confirm" } }
    }
    assert_response :unprocessable_entity

    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post room_ai_deliverable_review_path(@room), params: {
      deliverable: { kind: "client_brief", text: @text,
        revision_text: @text, intent: "compare" }
    }
    assert_response :forbidden
    assert_not_includes response.body, "Investigate checkout"
  end

  test "typed items use consistent accessible native-backed decision pickers" do
    grant_all
    post room_ai_deliverable_review_path(@room),
      params: { deliverable: { kind: "client_brief", text: @text } }
    assert_response :success
    assert_select "#h4-typed-results .sd-ai-picker-field", count: 2
    assert_select "#h4-typed-results select[name^='deliverable[decisions]']", count: 2
    assert_select "#h4-typed-results .sd-archive-picker__trigger", count: 2
  end
end
