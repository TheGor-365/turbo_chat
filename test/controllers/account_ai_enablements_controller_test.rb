require "test_helper"

class AccountAiEnablementsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice, @bob = users(:one), users(:two)
  end

  test "read is side effect free and anonymous writes are denied" do
    get account_ai_enablement_path, as: :json
    assert_response :unauthorized
    patch account_ai_enablement_path, params: {enabled: false, expected_revision: 0}, as: :json
    assert_response :unauthorized
    sign_in @alice
    assert_no_difference "AiPersonalEnablement.count" do
      get account_ai_enablement_path, as: :json
      assert_response :success
      assert_equal({"enabled" => true, "configured" => false, "revision" => 0}, response.parsed_body)
    end
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "personal state is independent and stale or forged writes fail" do
    sign_in @alice
    assert_no_difference ["AiRoomContextConsent.count", "AiAccountWritingPreference.count", "AiRoomWritingPreference.count", "Message.count", "AiUsageReservation.count"] do
      patch account_ai_enablement_path, params: {enabled: false, expected_revision: 0}, as: :json
      assert_response :success
      assert_equal({"enabled" => false, "configured" => true, "revision" => 1}, response.parsed_body)
      patch account_ai_enablement_path, params: {enabled: true, expected_revision: 0}, as: :json
      assert_response :conflict
      patch account_ai_enablement_path, params: {enabled: true, expected_revision: 1, user_id: @bob.id}, as: :json
      assert_response :unprocessable_entity
      assert_equal false, AiPersonalEnablement.find_by!(user: @alice).enabled
      patch account_ai_enablement_path, params: {enabled: true, expected_revision: 1}, as: :json
      assert_response :success
      assert_equal 2, response.parsed_body.fetch("revision")
      patch account_ai_enablement_path, params: {enabled: false, expected_revision: 2}, as: :json
      assert_response :success
      assert_equal 3, response.parsed_body.fetch("revision")
    end
    sign_out @alice
    sign_in @bob
    get account_ai_enablement_path, as: :json
    assert_equal({"enabled" => true, "configured" => false, "revision" => 0}, response.parsed_body)
    assert_nil AiPersonalEnablement.find_by(user: @bob)
  end

  test "only strict boolean and integer JSON is accepted" do
    sign_in @alice
    [{enabled: "false", expected_revision: 0}, {enabled: nil, expected_revision: 0},
      {enabled: false, expected_revision: "0"}, {enabled: false, expected_revision: -1},
      {enabled: false}].each do |bad|
      patch account_ai_enablement_path, params: bad, as: :json
      assert_response :unprocessable_entity
    end
    patch account_ai_enablement_path, params: {enabled: false, expected_revision: 0}
    assert_response :unsupported_media_type
    assert_nil AiPersonalEnablement.find_by(user: @alice)
  end
end
