require "test_helper"

class RoomAiDeliverablesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @message = @room.messages.create!(user: @bob, body: "Investigate HTTP 422 on POST orders.")
    @text = "## Requirements\n- Diagnose HTTP 422 [M#{@message.id}]\n" \
      "## Open Questions\n- Deadline: To confirm"
    sign_in @alice
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def save_draft
    post room_ai_deliverables_path(@room),
      params: { deliverable: { kind: "client_brief", text: @text } }
  end

  test "save is explicit and creates only draft v1, no message or approval" do
    grant_all
    baseline = Message.count
    assert_difference ["AiDeliverable.count", "AiDeliverableRevision.count"], 1 do
      save_draft
    end
    assert_response :redirect
    item = AiDeliverable.last
    assert_equal "draft", item.state
    assert_equal @alice, item.owner
    assert_equal [1], item.revisions.pluck(:version)
    assert_equal [@message.id], item.latest_revision.source_message_ids
    assert_equal baseline, Message.count
    follow_redirect!
    assert_response :success
    assert_select "#h5-saved-document", /Version 1/
    assert_select "a[href=?]", room_path(@room, focus: @message.id), minimum: 1
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "new version is appended, old version remains and stale update fails" do
    grant_all
    save_draft
    item = AiDeliverable.last
    changed = @text.sub("Deadline: To confirm", "Budget: To confirm")
    patch room_ai_deliverable_path(@room, item), params: {
      deliverable: { text: changed, expected_version: 1 }
    }
    assert_response :redirect
    assert_equal [1, 2], item.revisions.order(:version).pluck(:version)
    assert_equal @text, item.revisions.find_by!(version: 1).body_markdown
    assert_equal changed, item.revisions.find_by!(version: 2).body_markdown
    patch room_ai_deliverable_path(@room, item), params: {
      deliverable: { text: @text, expected_version: 1 }
    }
    assert_response :unprocessable_entity
    assert_equal 2, item.revisions.count
    get room_ai_deliverable_path(@room, item, version: 1)
    assert_response :success
    assert_select "textarea[readonly]", text: /Deadline: To confirm/
  end

  test "saved v2 shows exact changed lines, v1 remains unchanged, and no approval" do
    grant_all
    save_draft
    item = AiDeliverable.last
    updated = @text.sub("Deadline: To confirm", "Deadline: Awaiting client reply")
    patch room_ai_deliverable_path(@room, item), params: {
      deliverable: { text: updated, expected_version: 1 }
    }
    assert_response :redirect
    get room_ai_deliverable_path(@room, item)
    assert_response :success
    assert_select "#h5-version-diff" do
      assert_select "[data-change='added']", text: /Awaiting client reply/
      assert_select "[data-change='removed']", text: /Deadline: To confirm/
      assert_select "[data-change='unchanged']", minimum: 1
      assert_select "span", text: /1 added/
      assert_select "span", text: /1 removed/
    end
    assert_equal "draft", item.reload.state
    assert_equal @text, item.revisions.find_by!(version: 1).body_markdown
    get room_ai_deliverable_path(@room, item, version: 1)
    assert_response :success
    assert_select "#h5-version-diff", count: 0
  end

  test "revoked room consent denies reading and writing previously saved content" do
    grant_all
    save_draft
    item = AiDeliverable.last
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get room_ai_deliverable_path(@room, item)
    assert_response :forbidden
    assert_not_includes response.body, "Diagnose HTTP 422"
    patch room_ai_deliverable_path(@room, item), params: {
      deliverable: { text: @text, expected_version: 1 }
    }
    assert_response :forbidden
    assert_equal 1, item.revisions.count
  end

  test "foreign users or forged room citations cannot save or access documents" do
    grant_all
    save_draft
    item = AiDeliverable.last
    foreign = Room.create!(name: "H5 Foreign", is_private: true,
      kind: "private_group", owner: @bob)
    foreign.participants.create!(user: @bob, group_role: "owner")
    another_message = foreign.messages.create!(user: @bob, body: "Foreign private secret")
    post room_ai_deliverables_path(@room), params: {
      deliverable: { kind: "client_brief",
        text: "## Requirements\n- Expose [M#{another_message.id}]" }
    }
    assert_response :unprocessable_entity
    assert_equal 1, AiDeliverable.count
    sign_out @alice
    sign_in @bob
    get room_ai_deliverable_path(@room, item)
    assert_response :not_found
    assert_not_includes response.body, "Diagnose HTTP 422"
  end

  test "uncited question-only draft is readable and still private" do
    grant_all
    post room_ai_deliverables_path(@room), params: {
      deliverable: { kind: "client_brief",
        text: "## Open Questions\n- Deadline: To confirm" }
    }
    assert_response :redirect
    item = AiDeliverable.last
    assert_empty item.latest_revision.source_message_ids
    get room_ai_deliverable_path(@room, item)
    assert_response :success
    assert_select "#h5-saved-document", /Deadline: To confirm/
  end

  test "saved document from departed author is not served to remaining members" do
    third = User.create!(email: "h5-third-#{SecureRandom.hex(5)}@example.test",
      password: "TestPassword123!")
    group = Room.create!(name: "Private H5 source #{SecureRandom.hex(3)}",
      kind: "private_group", is_private: true, owner: @alice)
    [@alice, @bob, third].each do |person|
      group.participants.create!(user: person, group_role: person == @alice ? "owner" : "member")
      AiRoomContextConsent.find_or_initialize_by(room: group, user: person).grant!
    end
    evidence = group.messages.create!(user: third, body: "Team notes for launch")
    post room_ai_deliverables_path(group), params: {
      deliverable: { kind: "client_brief",
        text: "## Requirements\n- Launch notes [M#{evidence.id}]" }
    }
    assert_response :redirect
    item = AiDeliverable.last
    group.participants.where(user: third).delete_all
    get room_ai_deliverable_path(group, item)
    assert_response :forbidden
    assert_not_includes response.body, "Launch notes"
  end

  test "saved drafts are discoverable from AI Workspace, no automatic records" do
    grant_all
    get room_ai_workspace_path(@room)
    assert_response :success
    assert_select "a[href=?][aria-label='Open saved documents']",
      room_ai_deliverables_path(@room), count: 1
    get room_ai_deliverables_path(@room)
    assert_response :success
    assert_select "#h5-saved-documents", /No saved documents yet/
    assert_equal 0, AiDeliverable.count
    save_draft
    get room_ai_deliverables_path(@room)
    assert_response :success
    assert_select "#h5-saved-documents a[href=?]",
      room_ai_deliverable_path(@room, AiDeliverable.last), count: 1
  end

  test "deletion requires separate typed confirmation and removes all revisions" do
    grant_all
    save_draft
    item = AiDeliverable.last
    delete room_ai_deliverable_path(@room, item), params: { confirm: "YES" }
    assert_response :unprocessable_entity
    assert AiDeliverable.exists?(item.id)
    assert_difference ["AiDeliverable.count", "AiDeliverableRevision.count"], -1 do
      delete room_ai_deliverable_path(@room, item), params: { confirm: "DELETE" }
    end
    assert_response :redirect
    assert_equal 1, @room.messages.count
  end

  test "browser CRLF submissions are stored and exported as canonical LF Markdown" do
    grant_all
    original = Message.count
    windows_newlines = @text.gsub("\n", "\r\n")
    post room_ai_deliverables_path(@room), params: {
      deliverable: { kind: "client_brief", text: windows_newlines }
    }
    assert_response :redirect
    item = AiDeliverable.last
    assert_equal @text, item.latest_revision.body_markdown
    assert_equal Digest::SHA256.hexdigest(@text), item.latest_revision.body_sha256

    update = @text.sub("Deadline: To confirm", "Budget: To confirm")
    patch room_ai_deliverable_path(@room, item), params: {
      deliverable: { text: update.gsub("\n", "\r\n"), expected_version: 1 }
    }
    assert_response :redirect
    assert_equal update, item.latest_revision.body_markdown
    get export_room_ai_deliverable_path(@room, item, version: 2, format: :md)
    assert_response :success
    assert_equal update, response.body
    assert_equal original, Message.count
  end

  test "owner explicitly exports a chosen immutable Markdown or text version, never sends a chat message" do
    grant_all
    save_draft
    item = AiDeliverable.last
    revised = @text.sub("Deadline: To confirm", "Deadline: Awaiting client reply")
    patch room_ai_deliverable_path(@room, item),
      params: { deliverable: { text: revised, expected_version: 1 } }
    assert_response :redirect

    original_messages = Message.count
    get room_ai_deliverable_path(@room, item, version: 1)
    assert_response :success
    assert_select "a[href=?]",
      export_room_ai_deliverable_path(@room, item, version: 1, format: :md), count: 1
    assert_select "a[href=?]",
      export_room_ai_deliverable_path(@room, item, version: 1, format: :txt), count: 1

    get export_room_ai_deliverable_path(@room, item, version: 1, format: :md)
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "relay-client-brief-v1.md"
    assert_equal @text, response.body
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    get export_room_ai_deliverable_path(@room, item, version: 2, format: :txt)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.headers["Content-Disposition"], "relay-client-brief-v2.txt"
    assert_equal revised, response.body
    assert_equal [1, 2], item.revisions.order(:version).pluck(:version)
    assert_equal "draft", item.reload.state
    assert_equal original_messages, Message.count
  end

  test "export denies invalid format/version, revoked consent and non-owner" do
    grant_all
    save_draft
    item = AiDeliverable.last
    get export_room_ai_deliverable_path(@room, item, version: 999, format: :md)
    assert_response :forbidden
    assert_not_includes response.body, "Diagnose HTTP 422"
    get export_room_ai_deliverable_path(@room, item, version: 1, format: :json)
    assert_response :not_acceptable
    get export_room_ai_deliverable_path(@room, item, version: 1, format: :md)
    assert_response :success

    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get export_room_ai_deliverable_path(@room, item, version: 1, format: :md)
    assert_response :forbidden
    assert_not_includes response.body, "Diagnose HTTP 422"
    AiRoomContextConsent.find_by!(room: @room, user: @bob).grant!

    sign_out @alice
    sign_in @bob
    get export_room_ai_deliverable_path(@room, item, version: 1, format: :md)
    assert_response :not_found
    assert_not_includes response.body, "Diagnose HTTP 422"
  end

  test "export denies evidence from an author who left a private room" do
    grant_all
    save_draft
    item = AiDeliverable.last
    @room.participants.where(user: @bob).delete_all
    get export_room_ai_deliverable_path(@room, item, version: 1, format: :md)
    assert_response :forbidden
    assert_not_includes response.body, "Diagnose HTTP 422"
  end

  test "normal H4 review exposes optional Save draft but creates no record" do
    grant_all
    get new_room_ai_deliverable_review_path(@room)
    assert_response :success
    assert_select "form#h4-document-editor", count: 1
    assert_select "button[aria-label='Save private draft'][form=h4-document-editor][formaction=?]",
      room_ai_deliverables_path(@room), count: 1
    assert_equal 0, AiDeliverable.count
  end
end
