# frozen_string_literal: true
require "test_helper"

class LocalizedAvatarGuardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "rejected avatar produces a localized alert without touching account attributes" do
    user = users(:one)
    sign_in user
    original = user.reload.attributes.slice("email", "display_name", "updated_at")
    %w[en ru hy es].each do |locale|
      get edit_user_registration_path, params: { ui_locale: locale }
      assert_response :success
      put user_registration_path, params: {
        user: { email: "must-not-save@example.test",
                current_password: "incorrect-password",
                avatar: "not-a-multipart-upload" }
      }
      assert_redirected_to edit_user_registration_path
      assert_equal I18n.t("ui.upload.direct_not_supported", locale: locale), flash[:alert]
      assert_equal original,
        user.reload.attributes.slice("email", "display_name", "updated_at")
    end
  end
end
