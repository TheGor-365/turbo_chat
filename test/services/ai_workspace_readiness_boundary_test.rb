require "test_helper"

# Gate 2B.6 records negative, offline authorization invariants only.
# It does not pretend to exercise unimplemented consent, billing or AI.
class AiWorkspaceReadinessBoundaryTest < ActiveSupport::TestCase
  test "a former DM participant cannot reuse a previously valid selected preview or own draft" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room(
      [alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}"
    )
    source = room.messages.create!(user: bob, body: "Private discussion")
    selected = [source.id.to_s]
    preset = AiWorkspace::PresetRegistry.bundled.for_operation("summarize").first
    pipeline = AiWorkspace::ContentPipeline.new

    preview = pipeline.prepare(
      actor: alice, room: room, source: "selected_messages",
      source_ids: selected, operation: "summarize", preset: preset
    )
    assert_equal [source.id], preview.rows.map(&:source_id)

    # Access is checked again on every request, not inherited from the
    # earlier valid preview or the caller's saved source ID.
    room.participants.where(user: alice).delete_all

    assert_raises(AiWorkspace::Scope::Unauthorized) do
      AiWorkspace::Scope.new(
        room: room, actor: alice, operation: "summarize", message_ids: selected
      ).review
    end
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(
        actor: alice, room: room, source: "selected_messages",
        source_ids: selected, operation: "summarize", preset: preset
      )
    end

    draft_preset = AiWorkspace::PresetRegistry.bundled.for_operation("beautify").first
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(
        actor: alice, room: room, source: "own_draft",
        source_ids: [], operation: "beautify", preset: draft_preset,
        draft_text: "Former member's private text"
      )
    end
    assert_not AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!(preview)
    end
  end

  test "a public room is not an implicit grant even for offline own-draft preparation" do
    alice = users(:one)
    room = Room.create!(name: "Gate 2B6 public preview")
    preset = AiWorkspace::PresetRegistry.bundled.for_operation("beautify").first
    pipeline = AiWorkspace::ContentPipeline.new
    payload = {
      actor: alice, room: room, source: "own_draft",
      source_ids: [], operation: "beautify", preset: preset,
      draft_text: "A manually typed draft"
    }

    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(**payload)
    end

    membership = room.joinables.create!(user: alice)
    preview = pipeline.prepare(**payload)
    assert_equal "A manually typed draft", preview.rows.first.text
    assert_nil preview.rows.first.source_id

    membership.destroy!
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(**payload)
    end
    assert_not AiWorkspace::Gateway.configured?
  end

  test "selected history cannot smuggle a cross-room source to the disabled gateway" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room(
      [alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}"
    )
    foreign = Room.create!(name: "Gate 2B6 unrelated room")
    foreign.joinables.create!(user: bob)
    unrelated = foreign.messages.create!(user: bob, body: "Not in this room")

    preset = AiWorkspace::PresetRegistry.bundled.for_operation("summarize").first
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ContentPipeline.new.prepare(
        actor: alice, room: room, source: "selected_messages",
        source_ids: [unrelated.id.to_s],
        operation: "summarize", preset: preset
      )
    end
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      AiWorkspace::ContentPipeline.new.prepare(
        actor: alice, room: room, source: "approved_context",
        source_ids: [], operation: "summarize", preset: preset
      )
    end
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) do
      AiWorkspace::Gateway.generate!
    end
  end
end
