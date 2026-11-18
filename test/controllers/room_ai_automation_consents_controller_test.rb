require "test_helper"

class RoomAiAutomationConsentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = room_ai_automation_consent_path(@room)
  end

  def flags(background: true, send: false, documents: false, base: 0)
    { consent: { base_revision: base, background_context_enabled: background,
      unattended_send_enabled: send, scheduled_outcomes_enabled: documents } }
  end

  test "only the current member can give explicit revocable permission" do
    get @url, as: :json
    assert_response :unauthorized
    sign_in @alice
    get @url, as: :json
    assert_response :success
    assert_nil response.parsed_body.fetch("consent")
    assert_equal "private, no-store", response.headers["Cache-Control"]

    patch @url, params: flags, as: :json
    assert_response :success
    assert_equal true, response.parsed_body.dig("consent", "background_context_enabled")
    assert_equal false, response.parsed_body.dig("execution", "unattended_send_active")
    assert_equal 1, response.parsed_body.fetch("current_revision")

    sign_out @alice
    sign_in @bob
    get @url, as: :json
    assert_nil response.parsed_body.fetch("consent")
    sign_out @bob
    sign_in @alice
    delete @url, params: { consent: { base_revision: 1 } }, as: :json
    assert_response :success
    assert_equal false, response.parsed_body.dig("consent", "background_context_enabled")
    assert_equal 2, response.parsed_body.fetch("current_revision")
    assert_equal 0, @room.messages.count
    assert_equal 0, AiUsageReservation.count
  end

  test "forged fields, stale revisions, implicit flags and public rooms are denied" do
    sign_in @alice
    invalid = [
      { consent: flags.fetch(:consent).merge(auto_send: true) },
      flags(background: false, send: true),
      flags(background: true, send: "1"),
      flags.merge(consent: flags.fetch(:consent).except(:base_revision))
    ]
    invalid.each do |payload|
      patch @url, params: payload, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal 0, AiRoomAutomationConsent.count
    patch @url, params: flags, as: :json
    assert_response :success
    patch @url, params: flags(send: true), as: :json
    assert_response :conflict

    outsider = User.create!(email: "background-outsider@example.test",
      password: "test-password-123")
    sign_out @alice
    sign_in outsider
    patch @url, params: flags, as: :json
    assert_response :forbidden
    sign_out outsider
    sign_in @alice
    public_room = Room.create!(name: "Background access public", kind: "public_room",
      is_private: false)
    public_room.joinables.create!(user: @alice)
    patch room_ai_automation_consent_path(public_room), params: flags, as: :json
    assert_response :forbidden
  end
end
