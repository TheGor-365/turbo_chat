require "test_helper"

class RoomAiCoverageMessagePreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  def source_path(id, room: @room)
    room_ai_coverage_message_preview_path(room, message_id: id)
  end

  test "authenticated consenting member explicitly reads one safe source only" do
    grant_all
    allowed = @room.messages.create!(user: @bob, body: "Scope: fix the Rails login flow.")
    other = @room.messages.create!(user: @alice, body: "An unrelated confidential note")
    sign_in @alice
    before = Message.count

    get source_path(allowed.id), as: :json
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal({
      "version" => 1, "state" => "local_review_only",
      "message_id" => allowed.id,
      "updated_at" => allowed.updated_at.utc.iso8601(6),
      "text" => allowed.body
    }, response.parsed_body)
    assert_not_includes response.body, other.body
    assert_equal before, Message.count
  end

  test "consent revoked or never granted prevents reading any body" do
    msg = @room.messages.create!(user: @bob, body: "Need one small feature.")
    sign_in @alice
    get source_path(msg.id), as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, msg.body
    grant_all
    get source_path(msg.id), as: :json
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get source_path(msg.id), as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, msg.body
  end

  test "excluded messages are never revealed through a guessed source ID" do
    grant_all
    sensitive = @room.messages.create!(user: @bob, body: "Reach me at private@example.org")
    third = User.create!(email: "fcc-preview-former@example.test", password: "secure-password-123")
    @room.participants.create!(user: third)
    former = @room.messages.create!(user: third, body: "Former participant secret")
    @room.participants.where(user: third).delete_all
    blank = @room.messages.create!(user: @bob, body: "Temporary")
    blank.update_columns(body: "")
    sign_in @alice

    [sensitive, former, blank].each do |msg|
      get source_path(msg.id), as: :json
      assert_response :unprocessable_entity
      assert_not_includes response.body, msg.body if msg.body.present?
    end
    get source_path(999_999_999), as: :json
    assert_response :unprocessable_entity
    get source_path("nope"), as: :json
    assert_response :unprocessable_entity
  end

  test "out-of-room guessing, public room and outsider cannot access" do
    grant_all
    allowed = @room.messages.create!(user: @bob, body: "Room-only content")
    get source_path(allowed.id), as: :json
    assert_response :unauthorized

    outsider = User.create!(email: "fcc-preview-outsider@example.test", password: "secure-password-123")
    sign_in outsider
    get source_path(allowed.id), as: :json
    assert_response :forbidden
    assert_not_includes response.body, allowed.body
    sign_out outsider

    another = Room.create_private_room([@alice, outsider],
      "private_#{[@alice.id, outsider.id].sort.join('_')}")
    [@alice, outsider].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: another, user: user).grant!
    end
    sign_in @alice
    get source_path(allowed.id, room: another), as: :json
    assert_response :unprocessable_entity

    public_room = Room.create!(name: "No coverage body exposure")
    public_room.joinables.create!(user: @alice)
    get source_path(allowed.id, room: public_room), as: :json
    assert_response :forbidden
  end

  test "post-inventory body update with unchanged timestamp is rejected" do
    grant_all
    source = @room.messages.create!(user: @bob, body: "Initial agreement candidate")
    snapshot = Class.new do
      define_method(:initialize) { |room:, target:|
        @room, @target, @calls = room, target, 0
      }
      define_method(:build) { |room:, actor:|
        @calls += 1
        if @calls == 2
          @target.update_columns(body: "Rewritten after inventory")
        end
        AiWorkspace::ConversationCoverageSnapshotV2.new.build(room: room, actor: actor)
      }
    end.new(room: @room, target: source)

    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationCoverageMessageV1.new(snapshot: snapshot).call(
        room: @room, actor: @alice, message_id: source.id.to_s
      )
    end
  end

  test "peer-only grant permits that source but excludes the actor's ungranted history" do
    own = @room.messages.create!(user: @alice, body: "Withheld author note")
    peer = @room.messages.create!(user: @bob, body: "Permitted project scope")
    grant = AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob)
    grant.grant!
    sign_in @alice
    get source_path(peer.id), as: :json
    assert_response :success
    assert_equal peer.body, response.parsed_body.fetch("text")
    get source_path(own.id), as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, own.body
    grant.revoke!
    get source_path(peer.id), as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, peer.body
  end

end
