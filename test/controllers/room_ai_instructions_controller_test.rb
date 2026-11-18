require "test_helper"

class RoomAiInstructionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def payload(content, revision: 0)
    { instruction: {content: content, base_revision: revision} }
  end

  test "anonymous outsider and public room cannot read or edit private instructions" do
    get room_ai_instructions_path(@room)
    assert_redirected_to new_user_session_path
    patch room_ai_instructions_path(@room), params: payload("a"), as: :json
    assert_response :unauthorized

    outsider = User.create!(email: "room-instruction-outsider@example.test", password: "test-password-123")
    sign_in outsider
    get room_ai_instructions_path(@room), as: :json
    assert_response :forbidden
    get room_ai_instructions_history_path(@room), as: :json
    assert_response :forbidden
    patch room_ai_instructions_path(@room), params: payload("a"), as: :json
    assert_response :forbidden

    public_room = Room.create!(name: "PublicAiInstructionTest", kind: "public_room", is_private: false)
    public_room.joinables.create!(user: outsider)
    get room_ai_instructions_path(public_room), as: :json
    assert_response :forbidden
    patch room_ai_instructions_path(public_room), params: payload("a"), as: :json
    assert_response :forbidden
    assert_equal 0, RoomAiInstructionRevision.count
  end

  test "DM members see revisions, conflicting updates cannot overwrite, and unchanged updates are no-ops" do
    sign_in @alice
    get room_ai_instructions_path(@room), as: :json
    assert_response :success
    assert_equal 0, response.parsed_body.fetch("current_revision")
    assert_equal true, response.parsed_body.fetch("can_edit")
    assert_equal false, response.parsed_body.fetch("provider_inclusion")
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")

    patch room_ai_instructions_path(@room), params: payload("Rails 8 and no agreed price"), as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("current_revision")

    patch room_ai_instructions_path(@room), params: payload("stale update"), as: :json
    assert_response :conflict
    assert_equal 1, RoomAiInstructionRevision.count

    patch room_ai_instructions_path(@room), params: payload("Rails 8 and no agreed price", revision: 1), as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("changed")
    assert_equal 1, RoomAiInstructionRevision.count
    sign_out @alice

    sign_in @bob
    get room_ai_instructions_path(@room), as: :json
    assert_equal "Rails 8 and no agreed price", response.parsed_body.dig("current", "content")
    patch room_ai_instructions_path(@room), params: payload("Show open questions.", revision: 1), as: :json
    assert_response :success
    get room_ai_instructions_history_path(@room), as: :json
    assert_response :success
    assert_equal [2, 1], response.parsed_body.fetch("history").map { |row| row.fetch("revision_number") }
    assert_equal [@bob.chat_label, @alice.chat_label], response.parsed_body.fetch("history").map { |row| row.fetch("editor") }
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
  end

  test "group owner alone edits; membership transfer changes editor permission" do
    group = Room.create!(name: "Instructions Group", kind: "private_group", is_private: true, owner: @alice)
    group.participants.create!(user: @alice, group_role: "owner")
    group.participants.create!(user: @bob, group_role: "member")

    sign_in @bob
    get room_ai_instructions_path(group), as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("can_edit")
    patch room_ai_instructions_path(group), params: payload("not allowed"), as: :json
    assert_response :forbidden

    sign_out @bob
    sign_in @alice
    patch room_ai_instructions_path(group), params: payload("No signed budget"), as: :json
    assert_response :success

    group.with_lock do
      group.update!(owner: @bob)
      group.participants.find_by!(user: @alice).update!(group_role: "member")
      group.participants.find_by!(user: @bob).update!(group_role: "owner")
    end
    patch room_ai_instructions_path(group), params: payload("former owner", revision: 1), as: :json
    assert_response :forbidden
    sign_out @alice
    sign_in @bob
    patch room_ai_instructions_path(group), params: payload("new owner", revision: 1), as: :json
    assert_response :success
    assert_equal 2, group.ai_instruction_revisions.count
  end

  test "invalid data and unknown keys are rejected without a saved revision" do
    sign_in @alice
    [
      payload("x" * 4001), payload("A\x00B"), payload("spoof \u202e text"),
      {instruction: {content: "missing revision"}},
      {instruction: {content: "hello", base_revision: 0, automatic_send: true}},
      {instruction: {content: ["invalid array"], base_revision: 0}},
      {instruction: {content: "hello", base_revision: "NaN"}}
    ].each do |attributes|
      patch room_ai_instructions_path(@room), params: attributes, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, RoomAiInstructionRevision.count
  end

  test "clearing creates a new empty revision, deletion of author does not break history" do
    # Fixture one owns earlier messages in other rooms; use an isolated
    # synthetic author so this tests only the new audit-record FK behavior.
    @alice = User.create!(email: "instruction-audit-delete@example.test",
      password: "test-password-123")
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    sign_in @alice
    patch room_ai_instructions_path(@room), params: payload(""), as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("changed")
    patch room_ai_instructions_path(@room), params: payload("Synthetic glossary"), as: :json
    assert_response :success
    patch room_ai_instructions_path(@room), params: payload("", revision: 1), as: :json
    assert_response :success
    assert_equal 2, RoomAiInstructionRevision.count
    assert_equal "", RoomAiInstructionRevision.last.content

    sign_out @alice
    @room.participants.where(user: @alice).delete_all
    sign_in @alice
    get room_ai_instructions_history_path(@room), as: :json
    assert_response :forbidden
    patch room_ai_instructions_path(@room), params: payload("revoked", revision: 2), as: :json
    assert_response :forbidden
    sign_out @alice
    @alice.destroy!
    assert_nil RoomAiInstructionRevision.last.reload.editor_id
    assert_equal "Former member", RoomAiInstructionRevision.last.public_snapshot.fetch(:editor)
  end
end
