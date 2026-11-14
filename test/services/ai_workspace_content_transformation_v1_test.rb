# frozen_string_literal: true
require "test_helper"

class AiWorkspaceContentTransformationV1Test < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @message = @room.messages.create!(user: @bob,
      body: "Please prepare a client proposal. Budget and deadline are not agreed.")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
    @bundle = AiWorkspace::ReplyContextBuilder.new.build(
      room: @room, actor: @alice, hint: "Client proposal")
    @service = AiWorkspace::ContentTransformationV1.new
  end

  def plan(**overrides)
    @service.plan!(**{
      room: @room, actor: @alice, bundle: @bundle,
      task_kind: "client_proposal", preset_key: "agency/client_proposal",
      selected_source_ids: [@message.id]
    }.merge(overrides))
  end

  test "exactly three frozen business presets have existing H4 output schemas and version" do
    registry = AiWorkspace::BusinessPresetRegistryV1
    assert_equal 3, registry::PRESETS.size
    registry::PRESETS.each do |key, preset|
      assert_equal preset, registry.fetch!(key: key, version: 1)
      assert preset.frozen?
      assert preset.required_sections.frozen?
      assert preset.review_checks.frozen?
      assert_equal AiWorkspace::SemanticDeliverableGateV1::REQUIRED_SECTIONS.fetch(preset.task_kind),
        preset.required_sections
      assert_equal "explicit_save", preset.revision_policy
      assert_equal AiWorkspace::ConversationTaskV1.fetch!(preset.task_kind)[:max_output_tokens],
        preset.max_output_tokens
      assert_equal preset, registry.for_task(preset.task_kind)
    end
    assert_nil registry.for_task("action_items")
  end

  test "inert plan exposes only reviewed metadata and no provider, message or deliverable changes" do
    before = Message.count
    result = plan
    assert result.frozen?
    assert_equal 1, result.version
    assert_equal "agency/client_proposal", result.preset_key
    assert_equal 1, result.source_count
    assert_equal true, result.requires_human_review
    assert_equal "suggestion_only", result.execution_state
    assert_equal %w[problem approach deliverables exclusions assumptions next_steps], result.required_sections
    assert_includes result.review_checks, "approval"
    assert_not_includes result.to_h.to_json, @message.body
    assert_not_includes result.to_h.to_json, "participant_"
    assert_equal before, Message.count
  end

  test "wrong version, arbitrary preset or mismatched task fail closed" do
    assert_raises(AiWorkspace::Errors::InvalidPreset) { plan(preset_version: 2) }
    assert_raises(AiWorkspace::Errors::InvalidPreset) { plan(preset_key: "client_proposal") }
    assert_raises(AiWorkspace::Errors::InvalidPreset) { plan(task_kind: "client_brief") }
    assert_raises(AiWorkspace::Errors::InvalidPreset) { plan(preset_version: "1") }
  end

  test "unselected, forged and cross-room sources are rejected" do
    other_room = Room.create_private_room([@alice, @bob], "other_room_plan_#{@room.id}")
    foreign = other_room.messages.create!(user: @bob, body: "Other room private text")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      plan(selected_source_ids: [foreign.id])
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      plan(selected_source_ids: [@message.id, @message.id])
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      plan(selected_source_ids: [@message.id.to_s])
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) { plan(selected_source_ids: []) }
    assert_raises(AiWorkspace::Errors::InvalidSelection) { plan(bundle: @bundle.dup.tap { |b| b.room_id = other_room.id }) }
  end

  test "current consent and membership are mandatory even for offline planning" do
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) { plan }
    AiRoomContextConsent.find_by!(room: @room, user: @bob).grant!
    @room.participants.where(user: @alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) { plan }
  end

  test "an incoming message must remain in selected source IDs" do
    own = @room.messages.create!(user: @alice, body: "Owner note about client proposal")
    bundle = AiWorkspace::ReplyContextBuilder.new.build(room: @room, actor: @alice)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      plan(bundle: bundle, selected_source_ids: [own.id])
    end
  end
end
