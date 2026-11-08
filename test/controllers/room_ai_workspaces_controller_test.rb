require "test_helper"

class RoomAiWorkspacesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def direct_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "AI entry is visible only in an authorized conversation and stays unavailable" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    sign_in alice

    get room_path(room)
    assert_response :success
    assert_select "a.sd-ai-entry[href=?][aria-label=?]",
      room_ai_workspace_path(room), "AI Workspace — not configured", count: 1

    get room_ai_workspace_path(room)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "#ai-workspace .sd-ai-status", text: /AI is not configured/
    assert_select "#ai-workspace .sd-ai-future-state", text: /consent/
    assert_select "#ai-workspace form[action=?]", preview_room_ai_workspace_path(room)
    assert_select "a.sd-ai-back[href=?]", room_path(room)
    assert_select "#ai-scope-review", count: 0
    assert_not_includes response.body, bob.email
  end

  test "only authenticated active members can access AI review in private group and public room" do
    alice, bob = users(:one), users(:two)
    stranger = User.create!(email: "ai-workspace-outsider@example.test", password: "secure-password-123")
    private_room = direct_room(alice, bob)
    group = Room.create!(name: "AI private selection group", kind: "private_group",
      is_private: true, owner: alice)
    group.participants.create!(user: alice, group_role: "owner")
    group_message = group.messages.create!(user: alice, body: "Visible only to group members")
    public_room = Room.create!(name: "AI public read room")
    public_room.joinables.create!(user: bob)
    public_message = public_room.messages.create!(user: bob, body: "Public joined-only text")

    get room_ai_workspace_path(group)
    assert_redirected_to new_user_session_path
    post preview_room_ai_workspace_path(group),
      params: { review: { operation: "summarize", message_ids: [group_message.id.to_s] } }
    assert_redirected_to new_user_session_path

    sign_in stranger
    [private_room, group, public_room].each do |room|
      get room_ai_workspace_path(room)
      assert_response :forbidden
    end
    post preview_room_ai_workspace_path(group),
      params: { review: { operation: "summarize", message_ids: [group_message.id.to_s] } }
    assert_response :forbidden
    assert_not_includes response.body, group_message.body

    sign_out stranger
    sign_in alice
    get room_ai_workspace_path(group)
    assert_response :success
    get room_ai_workspace_path(public_room)
    assert_response :forbidden
    post preview_room_ai_workspace_path(public_room),
      params: { review: { operation: "summarize", message_ids: [public_message.id.to_s] } }
    assert_response :forbidden

    group.participants.where(user: alice).delete_all
    get room_ai_workspace_path(group)
    assert_response :forbidden
    post preview_room_ai_workspace_path(group),
      params: { review: { operation: "summarize", message_ids: [group_message.id.to_s] } }
    assert_response :forbidden
  end

  test "review shows only selected same-room texts, in chronology, never sends or stores a response" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: alice, body: "Original <img src=x onerror=alert(1)> private detail")
    other = room.messages.create!(user: bob, body: "Deliberately unselected secret marker")
    last = room.messages.create!(user: bob, body: "Final selected point")
    sign_in alice

    assert_no_difference(["Message.count", "Room.count"]) do
      post preview_room_ai_workspace_path(room), params: {
        review: { operation: "translate", message_ids: [last.id.to_s, first.id.to_s],
          room_id: "9999", provider: "paid", consent: "true" }
      }
    end
    assert_response :success
    assert_select "#ai-scope-review", text: /Selected context — local preview only/
    assert_select "#ai-scope-review [data-ai-preview-message-id]", count: 2
    assert_select "#ai-scope-review [data-ai-preview-message-id=?]", first.id.to_s, count: 1
    assert_select "#ai-scope-review [data-ai-preview-message-id=?]", last.id.to_s, count: 1
    assert_select "#ai-scope-review img", count: 0
    assert_select "#ai-scope-review", text: /Original <img src=x onerror=alert\(1\)> private detail/
    assert_select "#ai-scope-review", text: /Deliberately unselected secret marker/, count: 0
    assert_select "#ai-scope-review", text: /No AI response was generated or requested/
    assert_not_includes response.body, bob.email
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "forged cross-room and missing message IDs never disclose foreign content" do
    alice, bob = users(:one), users(:two)
    own = direct_room(alice, bob)
    own_message = own.messages.create!(user: alice, body: "Authorized selected line")
    foreign = Room.create!(name: "AI hidden exclusive", kind: "private_group",
      is_private: true, owner: bob)
    foreign.participants.create!(user: bob, group_role: "owner")
    hidden = foreign.messages.create!(user: bob, body: "Hidden model content 999")
    sign_in alice

    [hidden.id.to_s, "999999999999999999"].each do |bad_id|
      post preview_room_ai_workspace_path(own), params: {
        review: { operation: "summarize", message_ids: [own_message.id.to_s, bad_id] }
      }
      assert_response :unprocessable_entity
      assert_select ".sd-ai-error", text: /unavailable in this room/
      assert_select "#ai-scope-review", count: 0
      assert_not_includes response.body, hidden.body
      assert_not_includes response.body, foreign.name
    end
  end

  test "strict task and bounded id selection prevent broad unintended context" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    messages = 9.times.map { |i| room.messages.create!(user: alice, body: "AI selected line #{i}") }
    sign_in alice

    cases = [
      { operation: "bill_now", message_ids: [messages.first.id.to_s] },
      { operation: "summarize", message_ids: [] },
      { operation: "summarize", message_ids: messages.map { |m| m.id.to_s } },
      { operation: "summarize", message_ids: [messages.first.id.to_s] * 2 },
      { operation: "summarize", message_ids: ["1 OR 1=1"] }
    ]
    cases.each do |review|
      post preview_room_ai_workspace_path(room), params: { review: review }
      assert_response :unprocessable_entity
      assert_select ".sd-ai-error", count: 1
      assert_select "#ai-scope-review", count: 0
    end

    get room_ai_workspace_path(rooms(:two))
    assert_response :forbidden
  end

  test "long text is explicitly truncated in local review and no file bytes are included" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    msg = room.messages.create!(user: alice, body: "Z" * 3000)
    msg.attachments.attach(io: StringIO.new("TOP SECRET FILE BYTES"),
      filename: "private-review.txt", content_type: "text/plain")
    sign_in alice

    post preview_room_ai_workspace_path(room), params: {
      review: { operation: "summarize", message_ids: [msg.id.to_s] }
    }
    assert_response :success
    assert_select "#ai-scope-review .sd-ai-truncated", text: /limited to 750 characters/
    assert_not_includes response.body, "Z" * 751
    assert_not_includes response.body, "TOP SECRET FILE BYTES"
    assert_not_includes response.body, "private-review.txt"
  end

  test "no-provider gateway cannot be triggered by an injected adapter or token" do
    assert_not AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!(provider: "gpt", api_key: "not-a-real-key")
    end
  end
end
