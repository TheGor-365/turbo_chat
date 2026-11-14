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
      room_ai_workspace_path(room), "Chat history AI — selected messages only (offline)", count: 1

    get room_ai_workspace_path(room)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "#ai-workspace .sd-ai-status", text: /External AI is not configured/
    assert_select "#ai-workspace .sd-ai-future-state", text: /consent/
    assert_select "a.sd-ai-tool-link[href=?]", new_room_ai_deliverable_review_path(room), count: 1
    assert_select "a.sd-ai-tool-link[href=?]", room_path(room, ai_task: "client_brief"), count: 0
    assert_select ".sd-ai-tool-link--unavailable", text: /Requires xAI configuration/
    assert_select "#ai-workspace", text: /Automatic Client Brief/
    assert_select "#ai-workspace form[action=?]", preview_room_ai_workspace_path(room)
    assert_select "a.sd-ai-back[href=?]", room_path(room)
    assert_select "#ai-scope-review", count: 0
    assert_not_includes response.body, bob.email
  end

  test "configured semantic workspace reports actual room grants, not implied opt-in" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    sign_in alice
    AiRoomContextConsent.find_or_initialize_by(room: room, user: alice).grant!
    AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
      get room_ai_workspace_path(room)
      assert_response :success
      assert_select "#ai-workspace .sd-ai-policy-row", text: /1 \/ 2 current members granted access/
      assert_select "a.sd-ai-tool-link[href=?]",
        room_path(room, ai_task: "client_brief"), count: 1
      AiRoomContextConsent.find_or_initialize_by(room: room, user: bob).grant!
      get room_ai_workspace_path(room)
      assert_response :success
      assert_select "#ai-workspace .sd-ai-policy-row", text: /2 \/ 2 current members granted access/
    end
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


  test "preset selector exposes six offline profiles with generation disabled" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    sign_in alice

    get room_ai_workspace_path(room)
    assert_response :success
    assert_select "select[name='review[operation]'] option[value='beautify']", count: 1
    assert_select "select[name='review[preset_id]'] option", count: 6
    assert_select "select[name='review[preset_id]'] option[data-operation='beautify']", count: 3
    assert_select "select[name='review[preset_id]'] option[value='technical_summary'][selected]", count: 1
    assert_select "#ai-generate-unavailable[disabled]", text: /Generate unavailable/
    assert_select "#ai-scope-review", count: 0
    assert_not AiWorkspace::Gateway.configured?
  end

  test "matched preset renders only local manual preparation and never persists" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    chosen = room.messages.create!(user: alice, body: "Café client deadline not specified")
    ignored = room.messages.create!(user: bob, body: "UNSELECTED PRIVATE MARKER")
    sign_in alice

    assert_no_difference(["Message.count", "Room.count"]) do
      post preview_room_ai_workspace_path(room), params: {
        review: { operation: "summarize", preset_id: "technical_summary",
          message_ids: [chosen.id.to_s], ignored_provider: "paid", consent: "true" }
      }
    end
    assert_response :success
    assert_select "#ai-preset-review", text: /Technical Summary/
    assert_select "#ai-preset-review", text: /Preserve facts; do not invent prices or deadlines/
    assert_select "#ai-preset-review", text: /No model result, saved request, auto-send/
    assert_select "#ai-scope-review [data-ai-preview-message-id]", count: 1
    assert_select "#ai-scope-review", text: /UNSELECTED PRIVATE MARKER/, count: 0
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "mismatched, unknown, forged or inaccessible presets never expose a review" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: alice, body: "Authorized input")
    foreign = Room.create!(name: "Another private preset group", kind: "private_group",
      is_private: true, owner: bob)
    foreign.participants.create!(user: bob, group_role: "owner")
    hidden = foreign.messages.create!(user: bob, body: "FOREIGN_AI_PRIVATE_TEXT")
    sign_in alice

    [
      { operation: "summarize", preset_id: "polish_clarity", message_ids: [first.id.to_s] },
      { operation: "summarize", preset_id: "UNTRUSTED_MARKER", message_ids: [first.id.to_s] },
      { operation: "summarize", preset_id: "technical_summary", message_ids: [hidden.id.to_s] },
      { operation: "summarize", preset_id: "technical_summary", message_ids: [] }
    ].each do |review|
      post preview_room_ai_workspace_path(room), params: { review: review }
      assert_response :unprocessable_entity
      assert_select "#ai-preset-review", count: 0
      assert_select "#ai-scope-review", count: 0
      assert_not_includes response.body, hidden.body
      assert_not_includes response.body, foreign.name
      assert_not_includes response.body, "UNTRUSTED_MARKER"
    end

    room.participants.where(user: alice).delete_all
    post preview_room_ai_workspace_path(room), params: {
      review: { operation: "summarize", preset_id: "technical_summary",
        message_ids: [first.id.to_s] }
    }
    assert_response :forbidden
    assert_not_includes response.body, first.body
  end

  test "no-provider gateway cannot be triggered by an injected adapter or token" do
    assert_not AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!(provider: "gpt", api_key: "not-a-real-key")
    end
  end
end
