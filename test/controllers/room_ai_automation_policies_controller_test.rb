require "test_helper"

class RoomAiAutomationPoliciesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_automation_policy_path(@room)
  end

  def payload(mode: "review", summary_mode: "after_messages", revision: 0,
    kind: "conversation_summary")
    { policy: { base_revision: revision, reply_mode: mode,
      reply_delay_seconds: 30, summary_mode: summary_mode,
      summary_kind: kind, summary_after_messages: 20 } }
  end

  test "three modes are personal configurations only and never activate sending or spending" do
    get @url, as: :json
    assert_response :unauthorized

    sign_in @alice
    get @url, as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("configured")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal 0, response.parsed_body.fetch("current_revision")

    patch @url, params: payload, as: :json
    assert_response :success
    assert_equal "review", response.parsed_body.dig("policy", "reply_mode")
    assert_equal "after_messages", response.parsed_body.dig("policy", "summary_mode")
    assert_equal true, response.parsed_body.dig("execution", "configuration_only")
    assert_equal false, response.parsed_body.dig("execution", "reply_generation_active")
    assert_equal false, response.parsed_body.dig("execution", "scheduled_summaries_active")
    assert_equal false, response.parsed_body.dig("execution", "unattended_send_active")

    patch @url, params: payload(mode: "full_auto", revision: 1), as: :json
    assert_response :success
    assert_equal "full_auto", response.parsed_body.dig("policy", "reply_mode")
    assert_equal false, response.parsed_body.dig("execution", "unattended_send_active")
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
    assert_equal 1, AiAutomationPolicy.count
  end

  test "policy is isolated between members and survives a new GET" do
    sign_in @alice
    patch @url, params: payload, as: :json
    assert_response :success
    sign_out @alice
    sign_in @bob
    get @url, as: :json
    assert_nil response.parsed_body.fetch("policy")
    patch @url, params: payload(mode: "off", summary_mode: "manual"), as: :json
    assert_response :success
    sign_out @bob
    sign_in @alice
    get @url, as: :json
    assert_equal "review", response.parsed_body.dig("policy", "reply_mode")
    assert_equal "after_messages", response.parsed_body.dig("policy", "summary_mode")
  end

  test "stale revisions cannot overwrite configuration and explicit disable is safe" do
    sign_in @alice
    patch @url, params: payload, as: :json
    assert_response :success
    patch @url, params: payload(mode: "full_auto"), as: :json
    assert_response :conflict
    assert_equal 1, response.parsed_body.fetch("current_revision")
    patch @url, params: payload(revision: 1), as: :json
    assert_response :success
    assert_equal false, response.parsed_body.fetch("changed")
    assert_equal 1, response.parsed_body.fetch("current_revision")
    delete @url, params: { policy: { base_revision: 1 } }, as: :json
    assert_response :success
    assert_equal 2, response.parsed_body.fetch("current_revision")
    assert_equal "off", response.parsed_body.dig("policy", "reply_mode")
    assert_equal "off", response.parsed_body.dig("policy", "summary_mode")
    assert_equal 1, AiAutomationPolicy.count
    assert_equal 0, @room.messages.count
  end

  test "unexpected fields, invalid ranges and unauthorized users are rejected" do
    outsider = User.create!(email: "automation-outsider@example.test",
      password: "test-password-123")
    sign_in outsider
    get @url, as: :json
    assert_response :forbidden
    patch @url, params: payload, as: :json
    assert_response :forbidden
    sign_out outsider
    sign_in @alice
    invalid = [
      { policy: payload.fetch(:policy).merge(auto_send_enabled: true) },
      payload(mode: "unrestricted"),
      payload(kind: "read_private_files"),
      payload.merge(policy: payload.fetch(:policy).except(:base_revision)),
      { policy: payload.fetch(:policy).merge(reply_delay_seconds: -1) },
      { policy: payload.fetch(:policy).merge(summary_after_messages: 1000) },
      { policy: payload.fetch(:policy).merge(summary_mode: "hourly") }
    ]
    invalid.each do |data|
      patch @url, params: data, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, AiAutomationPolicy.count
    public_room = Room.create!(name: "Public automation gate", kind: "public_room", is_private: false)
    public_room.joinables.create!(user: @alice)
    patch room_ai_automation_policy_path(public_room), params: payload, as: :json
    assert_response :forbidden
  end
end
