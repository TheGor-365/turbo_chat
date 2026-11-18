require "test_helper"

class AiWorkspaceOutcomeTriggerProducerTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @policy = AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "off", summary_mode: "after_messages",
      summary_after_messages: 5, summary_kind: "conversation_summary")
    [@alice, @bob].each do |actor|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: actor).grant!
      AiRoomAutomationConsent.create!(room: @room, user: actor,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true,
        scheduled_outcomes_enabled: actor == @alice)
    end
    @time = Time.utc(2026, 11, 18, 13)
    @producer = AiWorkspace::OutcomeTriggerProducer.new(clock: -> { @time })
    @worker = AiWorkspace::AutomationOutcomeWorker.new
  end

  def add_message(text, user: @bob)
    @room.messages.create!(user: user, body: text)
  end

  test "after-N only counts messages newer than activation and deduplicates a window" do
    old = add_message("Prior scope is unrelated")
    AiOutcomeScheduleCursor.create!(ai_automation_policy: @policy,
      policy_revision: @policy.revision, last_message_id: old.id)
    4.times { |i| add_message("New task item #{i}") }
    assert_equal 0, @producer.scan_once!.enqueued
    assert_equal 0, AiAutomationWorkItem.count
    latest = add_message("Please review Rails validation and deadline")
    assert_equal 1, @producer.scan_once!.enqueued
    assert_equal 0, @producer.scan_once!.enqueued
    assert_equal 1, AiAutomationWorkItem.count
    run = AiAutomationRun.find_by!(room: @room, user: @alice)
    assert_equal old.id, run.source_after_message_id
    assert_equal latest.id, run.source_through_message_id
    assert_not_includes run.source_message_ids, old.id
    assert_equal true, @worker.process_one!
    assert_equal "completed", AiAutomationWorkItem.first.state
    assert_not_includes AiDeliverable.first.latest_revision.body_markdown, "Prior scope"
    assert_equal 0, @room.messages.where(user: @alice).count
  end

  test "no historical backfill when an older policy has no cursor" do
    5.times { |i| add_message("Old text #{i}") }
    assert_equal 0, @producer.scan_once!.enqueued
    cursor = AiOutcomeScheduleCursor.find_by!(ai_automation_policy: @policy)
    assert_equal @room.messages.maximum(:id), cursor.last_message_id
    assert_equal 0, AiAutomationRun.count
  end

  test "daily source is limited to preceding UTC day, and window is idempotent" do
    @policy.update!(summary_mode: "daily", revision: 2)
    @policy.update_columns(updated_at: Time.utc(2026, 11, 16, 12))
    earlier = add_message("Last week's unrelated contract")
    earlier.update_columns(created_at: Time.utc(2026, 11, 10, 10))
    in_day = add_message("Rails task summary for November 17")
    in_day.update_columns(created_at: Time.utc(2026, 11, 17, 10))
    assert_equal 1, @producer.scan_once!.enqueued
    assert_equal 0, @producer.scan_once!.enqueued # Idempotent: no second job
    assert_equal 1, AiAutomationWorkItem.count
    run = AiAutomationRun.first
    assert_equal Date.new(2026, 11, 17), run.source_utc_day
    assert_equal [in_day.id], run.source_message_ids
    assert_not_includes run.source_message_ids, earlier.id
    assert_equal true, @worker.process_one!
    assert_not_includes AiDeliverable.first.latest_revision.body_markdown,
      "Last week's unrelated contract"
  end

  test "revocation prevents enqueue and a changed source is blocked at processing" do
    AiOutcomeScheduleCursor.create!(ai_automation_policy: @policy,
      policy_revision: @policy.revision, last_message_id: 0)
    5.times { |i| add_message("Issue #{i} Rails") }
    AiRoomAutomationConsent.find_by!(room: @room, user: @bob).update!(
      background_context_enabled: false, revision: 2)
    assert_equal 0, @producer.scan_once!.enqueued
    assert_equal 0, AiAutomationWorkItem.count

    AiRoomAutomationConsent.find_by!(room: @room, user: @bob).update!(
      background_context_enabled: true, revision: 3)
    assert_equal 1, @producer.scan_once!.enqueued
    @room.messages.last.update!(body: "Now a different issue")
    assert @worker.process_one!
    assert_equal "blocked", AiAutomationWorkItem.first.state
    assert_equal 0, AiDeliverable.count
  end
end
