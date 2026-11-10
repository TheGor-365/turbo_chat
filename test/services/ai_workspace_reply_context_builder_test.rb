require "test_helper"

class AiWorkspaceReplyContextBuilderTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @access = AiWorkspace::RoomContextAccess.new
    @builder = AiWorkspace::ReplyContextBuilder.new
  end

  def grant(user)
    entry = AiRoomContextConsent.find_or_initialize_by(room: @room, user: user)
    entry.grant!
    entry
  end

  test "fail closed without every current private member grant" do
    @room.messages.create!(user: @bob, body: "Can you review this tomorrow?")
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @builder.build(room: @room, actor: @alice)
    end
    grant(@alice)
    status = @access.status(room: @room, actor: @alice)
    assert status.enabled
    assert_not status.ready
    assert_equal 1, status.granted
    assert_equal 2, status.members
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @builder.build(room: @room, actor: @alice)
    end
    grant(@bob)
    assert @access.status(room: @room, actor: @alice).ready
  end

  test "context includes bounded room-local chronology and never includes attachments or cross-room texts" do
    grant(@alice)
    grant(@bob)
    unrelated = Room.create!(name: "Unrelated public source")
    unrelated.joinables.create!(user: @bob)
    unrelated.messages.create!(user: @bob, body: "No access to this isolated context")
    m1 = @room.messages.create!(user: @bob, body: "The client asked about status.")
    m2 = @room.messages.create!(user: @alice, body: "I am checking the status.")
    m3 = @room.messages.create!(user: @bob, body: "Is there an ETA?")
    reply = @builder.build(room: @room, actor: @alice)
    assert_equal [m1.id, m2.id, m3.id], reply.source_ids
    other_tag = "participant_#{[@alice.id, @bob.id].sort.index(@bob.id) + 1}"
    assert_equal [other_tag, "you", other_tag], reply.rows.map(&:speaker)
    assert_equal reply.rows.sum { |row| row.text.length }, reply.characters
    assert_operator reply.characters, :<=, AiWorkspace::ReplyContextBuilder::MAX_CONTEXT_CHARS
    assert_not_includes reply.rows.map(&:text).join, "isolated context"
    assert reply.rows.all?(&:frozen?)
    assert reply.frozen?
  end

  test "PII and secrets are excluded without logging their values" do
    grant(@alice)
    grant(@bob)
    @room.messages.create!(user: @bob, body: "Email me: unsafe@example.test")
    @room.messages.create!(user: @bob, body: "Can you review the proposal?")
    @room.messages.create!(user: @bob, body: "ghp_abcdefghijklmnopqrstuvwxyz123456789")
    bundle = @builder.build(room: @room, actor: @alice)
    assert_equal ["Can you review the proposal?"], bundle.rows.map(&:text)
    assert_equal 2, bundle.omitted
  end

  test "revoke, leave and public room block all contextual retrieval" do
    grant(@alice)
    other = grant(@bob)
    @room.messages.create!(user: @bob, body: "A project update is required.")
    assert @builder.build(room: @room, actor: @alice)
    other.revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @builder.build(room: @room, actor: @alice)
    end
    other.grant!
    @room.participants.where(user: @alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @builder.build(room: @room, actor: @alice)
    end
    public_room = Room.create!(name: "Public consent test")
    public_room.joinables.create!(user: @alice)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @builder.build(room: public_room, actor: @alice)
    end
  end

  test "bounded retrieval will not guess a reply with no incoming text" do
    grant(@alice)
    grant(@bob)
    @room.messages.create!(user: @alice, body: "A note to myself")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      @builder.build(room: @room, actor: @alice)
    end
  end

  test "retrieves an older matching decision beyond the former 24-message horizon" do
    grant(@alice)
    grant(@bob)
    old = @room.messages.create!(user: @bob,
      body: "Proposal alpha requires a PostgreSQL audit before delivery.")
    33.times do |i|
      @room.messages.create!(user: i.even? ? @alice : @bob,
        body: "Unrelated weather check #{i} with generic filler.")
    end
    latest = @room.messages.create!(user: @bob,
      body: "What is the status of the proposal alpha PostgreSQL audit?")
    bundle = @builder.build(room: @room, actor: @alice)
    assert_includes bundle.source_ids, latest.id
    assert_includes bundle.source_ids, old.id
    assert_equal 2, bundle.retrieval_version
    assert_operator bundle.scanned_messages, :>, 24
    assert_operator bundle.characters, :<=, 2_400
    assert_equal bundle.source_ids.sort, bundle.source_ids
    assert bundle.frozen?
  end

  test "author hint changes relevant historical selections without creating any new messages" do
    grant(@alice)
    grant(@bob)
    first = @room.messages.create!(user: @bob,
      body: "Billing reconciliation requires an itemized invoice breakdown.")
    second = @room.messages.create!(user: @bob,
      body: "The release contract has an explicit warranty exclusion.")
    26.times do |i|
      @room.messages.create!(user: @alice,
        body: "Unrelated checkpoint #{i} for discussion.")
    end
    @room.messages.create!(user: @bob, body: "What should we do next?")
    before = Message.count
    with_hint = @builder.build(room: @room, actor: @alice,
      hint: "Focus on billing reconciliation and itemized invoice.")
    assert_includes with_hint.source_ids, first.id
    assert_not_includes with_hint.source_ids, second.id
    assert_equal before, Message.count
    assert_operator with_hint.rows.size, :<=, 9
  end

  test "private identifiers at the tail of an older message cannot enter the request" do
    grant(@alice)
    grant(@bob)
    flagged = @room.messages.create!(user: @bob,
      body: "Invoice reconciliation " + ("safe text " * 70) +
        "unsafe@example.test")
    valid = @room.messages.create!(user: @bob,
      body: "Invoice reconciliation needs line item clarification.")
    25.times do |i|
      @room.messages.create!(user: @alice, body: "Generic step #{i} for review.")
    end
    @room.messages.create!(user: @bob,
      body: "Please clarify invoice reconciliation.")
    bundle = @builder.build(room: @room, actor: @alice)
    assert_includes bundle.source_ids, valid.id
    assert_not_includes bundle.source_ids, flagged.id
    assert bundle.rows.all? { |row| row.text.length <= 420 }
    assert_operator bundle.characters, :<=, 2_400
  end

  test "older departed member content and unrelated rooms remain excluded" do
    grant(@alice)
    grant(@bob)
    outsider = User.create!(email: "context-departed@example.test",
      password: "secure-password-123")
    # A former member's historical message remains in the room, but is not
    # licensed by the two remaining members' consent.
    @room.participants.create!(user: outsider)
    departed = @room.messages.create!(user: outsider,
      body: "Proposal alpha private scope and a confidential schedule.")
    @room.participants.where(user: outsider).delete_all
    27.times do |i|
      @room.messages.create!(user: @alice, body: "Unrelated note #{i}.")
    end
    @room.messages.create!(user: @bob,
      body: "Please check the proposal alpha scope.")
    bundle = @builder.build(room: @room, actor: @alice)
    assert_not_includes bundle.source_ids, departed.id
    assert_not_includes bundle.rows.map(&:text).join(" "), "confidential schedule"
  end

  test "the retrieval window is finite and repeated calls are deterministic" do
    grant(@alice)
    grant(@bob)
    outside = @room.messages.create!(user: @bob,
      body: "Ancient release detail unavailable beyond bounded history.")
    246.times do |i|
      @room.messages.create!(user: @alice,
        body: "Daily review checkpoint #{i} for unrelated activity.")
    end
    newest = @room.messages.create!(user: @bob,
      body: "Which release detail is currently confirmed?")
    first = @builder.build(room: @room, actor: @alice)
    second = @builder.build(room: @room, actor: @alice)
    assert_equal first.source_ids, second.source_ids
    assert_includes first.source_ids, newest.id
    assert_not_includes first.source_ids, outside.id
    assert_equal 240, first.scanned_messages
    assert_operator first.rows.size, :<=, 9
    assert_operator first.characters, :<=, 2_400
  end
end
