require "test_helper"

class AiWorkspaceContextAuthorPolicyTest < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @policy = AiWorkspace::ContextAuthorPolicy.new
  end

  def grant(user)
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).tap(&:grant!)
  end

  test "no collective quorum: each author's historical grant is independent" do
    initial = @policy.resolve(room: @room, actor: @alice)
    assert_empty initial.allowed_author_ids
    assert_equal [@alice.id, @bob.id].sort, initial.withheld_author_ids
    assert_not initial.actor_history_granted
    assert_equal 2, initial.member_count

    grant(@alice)
    own = @policy.resolve(room: @room, actor: @alice)
    assert_equal [@alice.id], own.allowed_author_ids
    assert_equal [@bob.id], own.withheld_author_ids
    assert own.actor_history_granted

    grant(@bob)
    both = @policy.resolve(room: @room, actor: @alice)
    assert_equal [@alice.id, @bob.id].sort, both.allowed_author_ids
    assert_empty both.withheld_author_ids
    assert both.frozen?
    assert both.allowed_author_ids.frozen?
    assert both.withheld_author_ids.frozen?
  end

  test "revocation and removal drop an author's grant without changing others" do
    grant(@alice)
    bob_grant = grant(@bob)
    bob_grant.revoke!
    after_revoke = @policy.resolve(room: @room, actor: @alice)
    assert_equal [@alice.id], after_revoke.allowed_author_ids
    assert_equal [@bob.id], after_revoke.withheld_author_ids

    bob_grant.grant!
    @room.participants.where(user: @bob).delete_all
    after_leave = @policy.resolve(room: @room, actor: @alice)
    assert_equal [@alice.id], after_leave.allowed_author_ids
    assert_empty after_leave.withheld_author_ids
    assert_equal 1, after_leave.member_count
  end

  test "outsiders and public rooms have no author grant disclosure" do
    outsider = User.create!(email: "per-author-outsider@example.test",
      password: "secure-password-123")
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      @policy.resolve(room: @room, actor: outsider)
    end

    public_room = Room.create!(name: "Per author public rejection")
    public_room.joinables.create!(user: @alice)
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      @policy.resolve(room: public_room, actor: @alice)
    end
  end

  test "independent room eligibility does not require another member or own history grant" do
    access = AiWorkspace::RoomContextAccess.new
    initial = access.authorize_independent!(room: @room, actor: @alice)
    assert_empty initial.allowed_author_ids
    assert_not initial.actor_history_granted
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      access.authorize!(room: @room, actor: @alice)
    end
    grant(@bob)
    selection = access.authorize_independent!(room: @room, actor: @alice)
    assert_equal [@bob.id], selection.allowed_author_ids
    assert_not selection.actor_history_granted
    assert_equal [@alice.id], selection.withheld_author_ids
    @room.participants.where(user: @alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      access.authorize_independent!(room: @room, actor: @alice)
    end
  end

end
