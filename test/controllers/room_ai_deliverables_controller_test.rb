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
