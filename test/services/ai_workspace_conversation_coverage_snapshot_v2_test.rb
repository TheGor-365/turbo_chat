require "test_helper"

class AiWorkspaceConversationCoverageSnapshotV2Test < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @service = AiWorkspace::ConversationCoverageSnapshotV2.new
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "single-statement version inventory covers messages older than 240 without exposing bodies" do
    grant_all
    old = @room.messages.create!(user: @bob, body: "A confirmed early scope decision.")
    245.times { |i| @room.messages.create!(user: @alice, body: "Follow-up #{i}") }
    report = @service.build(room: @room, actor: @alice)
    assert_equal 2, report.version
    assert_equal 246, report.total_messages
    assert_equal 246, report.current_author_messages
    assert_equal 246, report.included_text_messages
    assert_equal 246, report.sources.length
    assert_equal old.id, report.sources.first.message_id
    assert_equal @room.messages.maximum(:id), report.watermark_message_id
    assert report.frozen?
    assert report.sources.frozen?
    assert report.sources.all?(&:frozen?)
    assert_match(/\A\h{64}\z/, report.source_sha256)
    assert_match(/\A\h{64}\z/, report.sources.first.version_sha256)
    assert_not_includes report.inspect, "A confirmed early scope decision."
    refute_respond_to report, :messages
    refute_respond_to report, :text
    assert_equal 0, @room.messages.where(body: "An AI response").count
  end

  test "classification is exhaustive and departed-author body is never exposed as a source" do
    grant_all
    third = User.create!(email: "fcc2-former@example.test", password: "secure-password-123")
    @room.participants.create!(user: third)
    former = @room.messages.create!(user: third, body: "Former secret meeting notes")
    @room.participants.where(user: third).delete_all
    clean = @room.messages.create!(user: @bob, body: "Check accepted Rails scope")
    unsafe = @room.messages.create!(user: @bob, body: "Email private@example.test")
    blank = @room.messages.create!(user: @alice, body: "Temporary message")
    blank.update_columns(body: "")

    report = @service.build(room: @room, actor: @alice)
    assert_equal 4, report.total_messages
    assert_equal 3, report.current_author_messages
    assert_equal 1, report.included_text_messages
    assert_equal 1, report.excluded_departed_author
    assert_equal 1, report.excluded_non_text
    assert_equal 1, report.excluded_sensitive
    assert_equal 0, report.excluded_invalid
    assert_equal [clean.id], report.sources.map(&:message_id)
    assert_not_includes report.inspect, "Former secret meeting notes"
    assert_not_includes report.inspect, unsafe.body
    assert_not_includes report.sources.map(&:message_id), former.id
    assert_equal report.total_messages,
      report.included_text_messages + report.excluded_departed_author +
        report.excluded_non_text + report.excluded_sensitive + report.excluded_invalid
  end

  test "no current unanimous consent or no membership means no snapshot" do
    @room.messages.create!(user: @bob, body: "Check this proposal")
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @service.build(room: @room, actor: @alice)
    end
    grant_all
    outsider = User.create!(email: "fcc2-outsider@example.test", password: "secure-password-123")
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @service.build(room: @room, actor: outsider)
    end
    @room.participants.where(user: @alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @service.build(room: @room, actor: @alice)
    end
  end

  test "oversized histories fail closed without a partial full coverage claim" do
    grant_all
    3.times { |i| @room.messages.create!(user: @bob, body: "Version #{i}") }
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationCoverageSnapshotV2.new(max_messages: 2).build(
        room: @room, actor: @alice)
    end
    assert_raises(ArgumentError) do
      AiWorkspace::ConversationCoverageSnapshotV2.new(max_messages: 10_001)
    end
  end

  test "concurrent content edit invalidates even if updated_at is unchanged" do
    grant_all
    source = @room.messages.create!(user: @bob, body: "Pending decision")
    original_time = source.updated_at
    @service.define_singleton_method(:after_snapshot) do |room:, actor:|
      source.update_columns(body: "Changed without timestamps")
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.build(room: @room, actor: @alice)
    end
    assert_equal original_time, source.reload.updated_at
  end

  test "concurrent delete and insert invalidate the first source snapshot" do
    grant_all
    original = @room.messages.create!(user: @bob, body: "Old ticket")
    @service.define_singleton_method(:after_snapshot) do |room:, actor:|
      Message.where(id: original.id).delete_all
      room.messages.create!(user: actor, body: "New ticket")
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.build(room: @room, actor: @alice)
    end
  end

  test "consent revocation between scan and validation fails closed" do
    grant_all
    @room.messages.create!(user: @bob, body: "Allowed until revoked")
    consent = AiRoomContextConsent.find_by!(room: @room, user: @bob)
    @service.define_singleton_method(:after_snapshot) do |room:, actor:|
      consent.revoke!
    end
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @service.build(room: @room, actor: @alice)
    end
  end

  test "regrant cannot silently reuse an earlier consent signature" do
    grant_all
    @room.messages.create!(user: @bob, body: "Allowed now")
    consent = AiRoomContextConsent.find_by!(room: @room, user: @bob)
    @service.define_singleton_method(:after_snapshot) do |room:, actor:|
      consent.revoke!
      consent.grant!
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @service.build(room: @room, actor: @alice)
    end
  end

  test "membership removal during source scan invalidates the snapshot" do
    grant_all
    @room.messages.create!(user: @bob, body: "Before removal")
    @service.define_singleton_method(:after_snapshot) do |room:, actor:|
      room.participants.where(user: actor).delete_all
    end
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @service.build(room: @room, actor: @alice)
    end
  end

  test "unchanged snapshots are stable; edit changes per-source version" do
    grant_all
    source = @room.messages.create!(user: @bob, body: "Original content")
    first = @service.build(room: @room, actor: @alice)
    second = @service.build(room: @room, actor: @alice)
    assert_equal first.source_sha256, second.source_sha256
    assert_equal first.sources.first.version_sha256, second.sources.first.version_sha256
    source.update!(body: "Revised content")
    third = @service.build(room: @room, actor: @alice)
    assert_not_equal second.source_sha256, third.source_sha256
    assert_not_equal second.sources.first.version_sha256, third.sources.first.version_sha256
  end
end
