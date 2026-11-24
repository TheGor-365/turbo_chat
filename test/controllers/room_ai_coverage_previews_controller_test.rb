require "test_helper"

class RoomAiCoveragePreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @path = room_ai_coverage_preview_path(@room)
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "authorized first page reports exhaustive exclusions and no raw message text" do
    grant_all
    third = User.create!(email: "fcc2b-former@example.test", password: "secure-password-123")
    @room.participants.create!(user: third)
    former = @room.messages.create!(user: third, body: "Former-member confidential text")
    @room.participants.where(user: third).delete_all
    allowed = @room.messages.create!(user: @bob, body: "Approved for audit preview only")
    unsafe = @room.messages.create!(user: @bob, body: "Do not send to unsafe@example.test")
    blank = @room.messages.create!(user: @alice, body: "Temporary text")
    blank.update_columns(body: "")
    original = Message.count
    sign_in @alice

    get @path, as: :json
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    result = response.parsed_body
    assert_equal "metadata_only_not_sent_to_ai", result.fetch("state")
    assert_equal 2, result.fetch("snapshot_version")
    assert_equal 4, result.dig("coverage", "total_messages")
    assert_equal 3, result.dig("coverage", "current_author_messages")
    assert_equal 1, result.dig("coverage", "eligible_safe_text")
    assert_equal 3, result.dig("coverage", "excluded_messages")
    assert_equal({"former_author" => 1, "withheld_author" => 0, "non_text" => 1,
      "sensitive" => 1, "invalid" => 0}, result.dig("coverage", "exclusions"))
    assert_equal [{"id" => allowed.id, "updated_at" => allowed.updated_at.utc.iso8601(6)}],
      result.fetch("sources")
    assert_equal false, result.dig("pagination", "has_more")
    assert_nil result.fetch("next_page_token")
    assert_not_includes response.body, allowed.body
    assert_not_includes response.body, unsafe.body
    assert_not_includes response.body, former.body
    assert_not_includes result.fetch("sources").map { |s| s.fetch("id") }, former.id
    assert_equal original, Message.count
  end

  test "next page must present an unchanged signed receipt and preserves result order" do
    grant_all
    created = 5.times.map do |index|
      @room.messages.create!(user: @bob, body: "Evidence checkpoint #{index}")
    end
    sign_in @alice
    get @path, params: { page_size: "2" }, as: :json
    assert_response :success
    first = response.parsed_body
    assert_equal [created[0].id, created[1].id], first.fetch("sources").map { |s| s.fetch("id") }
    assert_equal 3, first.dig("pagination", "total_pages")
    token = first.fetch("next_page_token")
    assert token.is_a?(String)
    assert_operator token.bytesize, :<, 4096

    get @path, params: { page: "2", page_size: "2", token: token }, as: :json
    assert_response :success
    second = response.parsed_body
    assert_equal [created[2].id, created[3].id], second.fetch("sources").map { |s| s.fetch("id") }
    assert_equal token, second.fetch("next_page_token")

    get @path, params: { page: "3", page_size: "2", token: token }, as: :json
    assert_response :success
    assert_equal [created[4].id], response.parsed_body.fetch("sources").map { |s| s.fetch("id") }
    assert_nil response.parsed_body.fetch("next_page_token")
  end

  test "altered or missing receipt, changed source body or page size are rejected" do
    grant_all
    target = 3.times.map { |i| @room.messages.create!(user: @bob, body: "Scope item #{i}") }.first
    sign_in @alice
    get @path, params: { page_size: "1" }, as: :json
    assert_response :success
    token = response.parsed_body.fetch("next_page_token")

    [{ page: "2", page_size: "1" },
     { page: "2", page_size: "1", token: "invalid" },
     { page: "2", page_size: "2", token: token }].each do |attributes|
      get @path, params: attributes, as: :json
      assert_response :unprocessable_entity
      assert_not_includes response.body, "Scope item"
    end

    target.update_columns(body: "Changed without updating the timestamp")
    get @path, params: { page: "2", page_size: "1", token: token }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Coverage preview unavailable or changed.", response.parsed_body.fetch("error")
  end

  test "revoked or renewed grants invalidate receipts and future requests" do
    grant_all
    3.times { |i| @room.messages.create!(user: @bob, body: "Milestone #{i}") }
    sign_in @alice
    get @path, params: { page_size: "1" }, as: :json
    assert_response :success
    token = response.parsed_body.fetch("next_page_token")
    consent = AiRoomContextConsent.find_by!(room: @room, user: @bob)
    consent.revoke!
    get @path, params: { page: "2", page_size: "1", token: token }, as: :json
    assert_response :unprocessable_entity

    consent.grant!
    get @path, params: { page: "2", page_size: "1", token: token }, as: :json
    assert_response :unprocessable_entity
    get @path, params: { page_size: "1" }, as: :json
    assert_response :success
  end

  test "outsiders, public rooms and unauthenticated requests cannot inspect" do
    grant_all
    @room.messages.create!(user: @bob, body: "Visible only to room participants")
    get @path, as: :json
    assert_response :unauthorized
    outsider = User.create!(email: "fcc2b-outsider@example.test", password: "secure-password-123")
    sign_in outsider
    get @path, as: :json
    assert_response :forbidden
    assert_not_includes response.body, "Visible only"
    sign_out outsider

    public_room = Room.create!(name: "No public coverage preview")
    public_room.joinables.create!(user: @alice)
    sign_in @alice
    get room_ai_coverage_preview_path(public_room), as: :json
    assert_response :forbidden
    get room_ai_coverage_preview_path(@room.id + 1_000_000), as: :json
    assert_response :not_found
  end

  test "invalid pagination and empty history never claim provider execution" do
    grant_all
    sign_in @alice
    get @path, as: :json
    assert_response :success
    empty = response.parsed_body
    assert_equal 0, empty.dig("coverage", "total_messages")
    assert_equal 1, empty.dig("pagination", "total_pages")
    assert_equal [], empty.fetch("sources")
    assert_nil empty.fetch("next_page_token")

    [{ page: "0" }, { page: "-1" }, { page: "2" }, { page_size: "51" },
      { page_size: "abc" }, { page: "1.5" }].each do |attributes|
      get @path, params: attributes, as: :json
      assert_response :unprocessable_entity
      assert_not_includes response.body, "token"
    end
    assert_equal 0, Message.where(room: @room).count
  end
end
