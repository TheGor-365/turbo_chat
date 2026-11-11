require "test_helper"

class AiWorkspaceSourceSelectionTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob, body: "Check the Rails API validation.")
    @older = @room.messages.create!(user: @bob, body: "Review PostgreSQL model constraints.")
    @own = @room.messages.create!(user: @alice, body: "I'll investigate the issue.")
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    @builder = AiWorkspace::ReplyContextBuilder.new
  end

  def bundle(hint: "")
    @builder.build(room: @room, actor: @alice, hint: hint)
  end

  test "signed preview allows only explicit chronological subset and keeps source metadata bounded" do
    original = bundle
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: original, hint: "")
    before = Message.count
    selected = AiWorkspace::SourceSelection.apply!(
      room: @room, actor: @alice, bundle: bundle, hint: "",
      source_token: token, selected_ids: [@older.id])
    assert_equal [@older.id], selected.source_ids
    assert_equal [@older.id], selected.rows.map(&:message_id)
    assert_equal selected.rows.first.text.length, selected.characters
    assert_equal original.omitted + original.rows.length - 1, selected.omitted
    assert_equal [@older.id], selected.selection_reasons.keys
    assert selected.frozen?
    assert selected.rows.frozen?
    assert_equal before, Message.count
    assert_equal original, AiWorkspace::SourceSelection.apply!(
      room: @room, actor: @alice, bundle: original, hint: "")
  end

  test "forged IDs, duplicates, missing token, invalid signature and all-own selection fail closed" do
    original = bundle
    token = AiWorkspace::SourceSelection.issue(room: @room,
      actor: @alice, bundle: original, hint: "")
    other = Room.create!(name: "Foreign", kind: "private_group",
      is_private: true, owner: @bob)
    other.participants.create!(user: @bob, group_role: "owner")
    foreign = other.messages.create!(user: @bob, body: "Private foreign room text.")
    invalid = [
      [token, [foreign.id]], [token, [@incoming.id, @incoming.id]],
      [token, [@own.id]], [nil, [@incoming.id]],
      ["fake-token", [@incoming.id]], [token, ["#{@incoming.id}"]],
      [token, []], [token, (1..10).to_a]
    ]
    invalid.each do |receipt, ids|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        AiWorkspace::SourceSelection.apply!(room: @room, actor: @alice,
          bundle: original, hint: "", source_token: receipt, selected_ids: ids)
      end
    end
  end

  test "content changes, changed hint, another actor and a new member invalidate the receipt" do
    original = bundle(hint: "Focus on validations.")
    token = AiWorkspace::SourceSelection.issue(room: @room,
      actor: @alice, bundle: original, hint: "Focus on validations.")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::SourceSelection.apply!(room: @room, actor: @alice,
        bundle: original, hint: "Focus on delivery.", source_token: token,
        selected_ids: [@incoming.id])
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::SourceSelection.apply!(room: @room, actor: @bob,
        bundle: original, hint: "Focus on validations.", source_token: token,
        selected_ids: [@incoming.id])
    end
    @incoming.update!(body: "The Rails validation error has changed.")
    fresh = bundle(hint: "Focus on validations.")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::SourceSelection.apply!(room: @room, actor: @alice,
        bundle: fresh, hint: "Focus on validations.", source_token: token,
        selected_ids: [@incoming.id])
    end
  end

  test "membership changes invalidate a previously signed preview even after new consent" do
    original = bundle
    token = AiWorkspace::SourceSelection.issue(room: @room,
      actor: @alice, bundle: original, hint: "")
    newcomer = User.create!(email: "snapshot-member@example.test",
      password: "safe-password-123")
    @room.participants.create!(user: newcomer)
    assert_raises(AiWorkspace::Errors::ConsentRequired) { bundle }
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: newcomer).grant!
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::SourceSelection.apply!(room: @room, actor: @alice,
        bundle: bundle, hint: "", source_token: token,
        selected_ids: [@incoming.id])
    end
  end
end
