require "test_helper"

class AiWorkspaceAutomationOutcomeWorkerTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "We should inspect the Rails validation failure before setting a date")
    @policy = AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "off", summary_mode: "after_messages",
      summary_kind: "conversation_summary")
    [@alice, @bob].each do |actor|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: actor).grant!
      AiRoomAutomationConsent.create!(room: @room, user: actor,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true, scheduled_outcomes_enabled: actor == @alice)
    end
    @registry = AiWorkspace::AutomationRunRegistry.new
    @worker = AiWorkspace::AutomationOutcomeWorker.new
  end

  def run
    @run ||= @registry.capture_outcome!(room: @room, actor: @alice,
      window_key: "after_messages:#{@incoming.id}")
  end

  test "explicit enqueue deduplicates and offline worker saves a private cited H5 draft" do
    first = @worker.enqueue!(run: run)
    again = @worker.enqueue!(run: run)
    assert_equal first.id, again.id
    assert_equal 1, AiAutomationWorkItem.count
    assert_equal "queued", first.state
    assert @worker.process_one!
    item = first.reload
    assert_equal "completed", item.state
    assert_equal 1, item.attempts
    assert_equal 0, @room.messages.where(user: @alice).count
    document = item.ai_deliverable
    assert_equal "draft", document.state
    assert_equal @alice, document.owner
    assert_equal @room, document.room
    assert_equal "conversation_summary", document.kind
    assert_equal 1, document.revisions.count
    assert_includes document.latest_revision.body_markdown, "[M#{@incoming.id}]"
    assert_equal [@incoming.id], document.latest_revision.source_message_ids
    assert_equal 64, document.latest_revision.body_sha256.length
    assert_equal false, AiWorkspace::Gateway.configured?
    assert_equal false, @worker.process_one!
    assert_equal 1, AiDeliverable.count
  end

  test "stale message or revoked background consent blocks queued work with no draft" do
    task = @worker.enqueue!(run: run)
    @incoming.update!(body: "The scope has now changed")
    assert @worker.process_one!
    assert_equal "blocked", task.reload.state
    assert_nil task.ai_deliverable
    assert_equal 0, AiDeliverable.count
    assert_equal 1, @room.messages.count
  end

  test "consent revoked after enqueue prevents document creation" do
    task = @worker.enqueue!(run: run)
    AiRoomAutomationConsent.find_by!(room: @room, user: @bob)
      .update!(background_context_enabled: false, revision: 2)
    assert @worker.process_one!
    assert_equal "blocked", task.reload.state
    assert_nil task.ai_deliverable
    assert_equal 0, AiDeliverable.count
  end

  test "reply events and non-offline document types cannot enter this worker" do
    @policy.update!(summary_kind: "open_questions", revision: 2)
    outcome = @registry.capture_outcome!(room: @room, actor: @alice,
      window_key: "after_messages:#{@incoming.id}")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @worker.enqueue!(run: outcome)
    end
    assert_equal 0, AiAutomationWorkItem.count
    assert_equal 0, AiDeliverable.count
  end

  test "no scheduled consent means no enqueue even when manual context consent exists" do
    AiRoomAutomationConsent.find_by!(room: @room, user: @alice)
      .update!(scheduled_outcomes_enabled: false, revision: 2)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @worker.enqueue!(run: run)
    end
    assert_equal 0, AiAutomationWorkItem.count
  end
end
