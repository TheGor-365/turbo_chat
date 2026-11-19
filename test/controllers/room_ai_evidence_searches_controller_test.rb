require "test_helper"

class RoomAiEvidenceSearchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @path = room_ai_evidence_search_path(@room)
  end

  def grant_all
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "explicit search only yields safe sources with source identifiers and no model invocation" do
    grant_all
    safe = @room.messages.create!(user: @bob,
      body: "Предлагаю сроки проекта на март")
    unsafe = @room.messages.create!(user: @alice,
      body: "Сроки проекта: secret@example.test")
    sign_in @alice
    count = @room.messages.count

    post @path, params: { evidence_query: "сроки проекта" }, as: :json
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    result = response.parsed_body
    assert_equal "local_lexical_evidence_candidates_not_ai", result.fetch("state")
    assert_equal [safe.id], result.fetch("results").map { |row| row.fetch("id") }
    assert_equal "proposal", result.dig("results", 0, "classification", "state")
    assert_equal "all_candidates_require_human_verification", result.fetch("review")
    timeline = result.fetch("chronology")
    assert_equal "unverified_candidate_chronology", timeline.fetch("state")
    assert_equal [safe.id], timeline.fetch("events").map { |row| row.fetch("id") }
    assert_equal "not_determined", timeline.fetch("approval_state")
    assert_equal true, timeline.fetch("requires_human_review")
    assert_not_includes response.body, unsafe.body
    assert_equal count, @room.messages.count
  end

  test "unauthenticated, outsider and public room cannot search private texts" do
    grant_all
    source = @room.messages.create!(user: @bob, body: "Project private milestone")
    post @path, params: { evidence_query: "private milestone" }, as: :json
    assert_response :unauthorized

    outsider = User.create!(email: "fcc2d-outsider@example.test", password: "secure-password-123")
    sign_in outsider
    post @path, params: { evidence_query: "private milestone" }, as: :json
    assert_response :forbidden
    assert_not_includes response.body, source.body
    sign_out outsider

    public_room = Room.create!(name: "Public evidence is forbidden")
    public_room.joinables.create!(user: @alice)
    sign_in @alice
    post room_ai_evidence_search_path(public_room),
      params: { evidence_query: "private milestone" }, as: :json
    assert_response :forbidden
    post room_ai_evidence_search_path(@room.id + 500000),
      params: { evidence_query: "private milestone" }, as: :json
    assert_response :not_found
  end

  test "missing or revoked consent and invalid query never disclose source bodies" do
    source = @room.messages.create!(user: @bob, body: "Rails contract proposal")
    sign_in @alice
    post @path, params: { evidence_query: "contract proposal" }, as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, source.body

    grant_all
    post @path, params: { evidence_query: "contract proposal" }, as: :json
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    post @path, params: { evidence_query: "contract proposal" }, as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, source.body

    post @path, params: { evidence_query: { nested: "contract proposal" } }, as: :json
    assert_response :unprocessable_entity
    assert_not_includes response.body, source.body
  end
end
