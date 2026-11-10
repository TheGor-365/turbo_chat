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
    foreign_room = Room.create_private_room([@alice, users(:two)],
      "private_#{[@alice.id, users(:two).id].sort.join('_')}")
    assert_equal @room.id, foreign_room.id
    unrelated = Room.create!(name: "Unrelated public source")
    unrelated.joinables.create!(user: @bob)
    unrelated.messages.create!(user: @bob, body: "No access to this isolated context")
    m1 = @room.messages.create!(user: @bob, body: "The client asked about status.")
    m2 = @room.messages.create!(user: @alice, body: "I am checking the status.")
    m3 = @room.messages.create!(user: @bob, body: "Is there an ETA?")
    reply = @builder.build(room: @room, actor: @alice)
    assert_equal [m1.id, m2.id, m3.id], reply.source_ids
    assert_equal %w[participant_2 you participant_2], reply.rows.map(&:speaker)
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
end
