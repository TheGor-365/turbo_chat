require "test_helper"

class RoomAiAutomationOutcomesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @path = room_ai_automation_outcomes_path(@room)
    @message = @room.messages.create!(user: @bob,
      body: "Please review Rails registration validations before acceptance")
    AiAutomationPolicy.create!(room: @room, user: @alice,
      reply_mode: "off", summary_mode: "after_messages",
      summary_kind: "conversation_summary")
  end

  def grant_context_and_background
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
      AiRoomAutomationConsent.create!(room: @room, user: person,
        member_set_fingerprint: AiRoomAutomationConsent.fingerprint_for(@room),
        background_context_enabled: true,
        scheduled_outcomes_enabled: person == @alice)
    end
  end

  test "owner sees only counts and index path; another participant sees no owner's jobs" do
    grant_context_and_background
    run = AiWorkspace::AutomationRunRegistry.new.capture_outcome!(
      room: @room, actor: @alice, window_key: "after_messages:#{@message.id}")
    worker = AiWorkspace::AutomationOutcomeWorker.new
    worker.enqueue!(run: run)

    sign_in @alice
    get @path, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("pending")
    assert_equal 0, response.parsed_body.fetch("completed")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert worker.process_one!

    get @path, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("completed")
    assert_equal 0, response.parsed_body.fetch("pending")
    assert_equal room_ai_deliverables_path(@room), response.parsed_body.fetch("documents_url")
    assert_equal false, response.parsed_body.fetch("provider_called")
    assert_equal false, response.parsed_body.fetch("automatic_send_active")
    assert_not_includes response.body, @message.body
    assert_equal 1, @room.messages.count

    sign_out @alice
    sign_in @bob
    get @path, as: :json
    assert_response :success
    assert_equal 0, response.parsed_body.fetch("completed")
  end

  test "unauthenticated, nonmember and revoked context cannot inspect status" do
    get @path, as: :json
    assert_response :unauthorized
    sign_in @alice
    get @path, as: :json
    assert_response :forbidden
    grant_context_and_background
    get @path, as: :json
    assert_response :success
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    get @path, as: :json
    assert_response :forbidden

    sign_out @alice
    outsider = User.create!(email: "status-outsider@example.test",
      password: "test-password-123")
    sign_in outsider
    get @path, as: :json
    assert_response :forbidden
  end
end
