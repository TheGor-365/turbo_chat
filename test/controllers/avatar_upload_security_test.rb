require "test_helper"
require "stringio"
require "tempfile"

class AvatarUploadSecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "registration accepts a genuine multipart JPEG avatar" do
    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: registration_params.merge(
          avatar: fixture_file_upload(Rails.root.join("app/assets/images/default_profile.jpg"), "image/jpeg")
        )
      }
    end

    assert_response :redirect
    assert User.find_by!(email: "avatar-guard@example.test").avatar.attached?
  end

  test "registration rejects HTML disguised as a PNG before creating the user" do
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: registration_params.merge(avatar: fixture_file_upload("upload_spoofed.html", "image/png"))
      }
    end

    assert_redirected_to new_user_registration_path
    assert_match(/content does not match|type is not allowed/, flash[:alert])
  end

  test "registration rejects a signed blob ID rather than bypassing inspection" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("not an image"), filename: "some-file.txt", content_type: "text/plain"
    )

    assert_no_difference "User.count" do
      post user_registration_path, params: { user: registration_params.merge(avatar: blob.signed_id) }
    end

    assert_redirected_to new_user_registration_path
    assert_match(/Direct uploads are not supported/, flash[:alert])
  end

  test "an oversized avatar is rejected before creating an account" do
    Tempfile.create(["large-avatar", ".png"]) do |file|
      file.binmode
      file.write("\x89PNG\r\n\x1A\n".b)
      file.write("x" * (5.megabytes + 1))
      file.flush

      assert_no_difference "User.count" do
        post user_registration_path, params: {
          user: registration_params.merge(avatar: Rack::Test::UploadedFile.new(file.path, "image/png"))
        }
      end
    end

    assert_redirected_to new_user_registration_path
    assert_match(/exceeds 5 MB/, flash[:alert])
  end

  test "profile update rejects spoofed avatar without changing account attributes" do
    user = users(:one)
    original_email = user.email
    sign_in user

    put user_registration_path, params: {
      user: {
        email: "hijacked@example.test", current_password: "test-password-123",
        avatar: fixture_file_upload("upload_spoofed.html", "image/png")
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_match(/content does not match|type is not allowed/, flash[:alert])
    assert_equal original_email, user.reload.email
  end

  test "profile update accepts an authentic multipart JPEG avatar" do
    user = users(:one)
    sign_in user

    put user_registration_path, params: {
      user: {
        email: user.email, current_password: "test-password-123",
        avatar: fixture_file_upload(Rails.root.join("app/assets/images/default_profile.jpg"), "image/jpeg")
      }
    }

    assert_response :redirect
    assert user.reload.avatar.attached?
  end

  private

  def registration_params
    {
      email: "avatar-guard@example.test",
      password: "avatar-test-password-123",
      password_confirmation: "avatar-test-password-123"
    }
  end
end
