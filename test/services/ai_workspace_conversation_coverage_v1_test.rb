require "test_helper"

class AiWorkspaceConversationCoverageV1Test < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def grant(user)
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).tap(&:grant!)
  end

  def grant_all
    grant(@alice)
    grant(@bob)
  end

  test "full inventory includes permitted text older than the 240-message retrieval window" do
    grant_all
    @room.messages.create!(user: @bob, body: "Old Rails scope decision")
    245.times do |i|
      @room.messages.create!(user: @alice, body: "Later checkpoint #{i}")
    end
    original_count = Message.count
    report = AiWorkspace::ConversationCoverageV1.new.build(room: @room, actor: @alice)
    assert_equal 1, report.version
    assert_equal 246, report.total_messages
    assert_equal 246, report.scanned_author_messages
    assert_equal 246, report.safe_text_messages
    assert_equal 0, report.filtered_former_author
    assert_match(/\A\h{64}\z/, report.source_sha256)
    assert report.frozen?
    assert_equal original_count, Message.count
    refute_respond_to report, :messages
    refute_respond_to report, :source_ids
  end

  test "former member text is not read and sensitive or blank text is filtered" do
    grant_all
    third = User.create!(email: "coverage-former@example.test", password: "secure-password-123")
    @room.participants.create!(user: third)
    @room.messages.create!(user: third, body: "Private departed-member content")
    @room.participants.where(user: third).delete_all
    @room.messages.create!(user: @bob, body: "Contact unsafe@example.test")
    @room.messages.create!(user: @bob, body: "Check the API contract")
    blank = @room.messages.create!(user: @alice, body: "Temporary note")
    blank.update_columns(body: "")

    report = AiWorkspace::ConversationCoverageV1.new.build(room: @room, actor: @alice)
    assert_equal 4, report.total_messages
    assert_equal 3, report.scanned_author_messages
    assert_equal 1, report.safe_text_messages
    assert_equal 1, report.filtered_former_author
    assert_equal 1, report.filtered_sensitive
    assert_equal 1, report.filtered_non_text
  end

  test "consent, access, public room and maximum-history gates fail closed" do
    @room.messages.create!(user: @bob, body: "First item")
    service = AiWorkspace::ConversationCoverageV1.new
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      service.build(room: @room, actor: @alice)
    end
    grant_all
    outsider = User.create!(email: "coverage-outsider@example.test", password: "secure-password-123")
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      service.build(room: @room, actor: outsider)
    end
    public_room = Room.create!(name: "Coverage public exclusion")
    public_room.joinables.create!(user: @alice)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      service.build(room: public_room, actor: @alice)
    end
    @room.messages.create!(user: @bob, body: "Second item")
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationCoverageV1.new(max_messages: 1).build(
        room: @room, actor: @alice)
    end
  end

  test "revoked grant at final check prevents returning the inventory" do
    grant_all
    @room.messages.create!(user: @bob, body: "Legitimate test message")
    consent = AiRoomContextConsent.find_by!(room: @room, user: @bob)
    access = Object.new
    original = AiWorkspace::RoomContextAccess.new
    checks = 0
    access.define_singleton_method(:authorize!) do |room:, actor:|
      checks += 1
      consent.revoke! if checks == 2
      original.authorize!(room: room, actor: actor)
    end
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      AiWorkspace::ConversationCoverageV1.new(access: access).build(
        room: @room, actor: @alice)
    end
    assert_equal 2, checks
  end

  test "later edit changes fingerprint without including source content in report" do
    grant_all
    message = @room.messages.create!(user: @bob, body: "Draft scope is pending")
    service = AiWorkspace::ConversationCoverageV1.new
    before = service.build(room: @room, actor: @alice)
    message.update!(body: "Scope is confirmed")
    after = service.build(room: @room, actor: @alice)
    assert_equal before.total_messages, after.total_messages
    assert_not_equal before.source_sha256, after.source_sha256
    assert_not_includes after.inspect, "Scope is confirmed"
  end
end
