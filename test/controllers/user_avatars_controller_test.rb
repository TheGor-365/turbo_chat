require "test_helper"
require "stringio"

class UserAvatarsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "anonymous avatar request requires authentication" do
    get user_avatar_path(users(:one))
    assert_redirected_to new_user_session_path
  end

  test "member sees an attached user avatar" do
    sign_in users(:one)
    users(:one).avatar.attach(io: StringIO.new("avatar-test"), filename: "avatar.jpg", content_type: "image/jpeg")
    assert users(:one).avatar.attached?
    get user_avatar_path(users(:one))
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_match %r{image/jpeg}, response.media_type
  end

  test "missing avatar owner yields 404" do
    sign_in users(:one)
    get user_avatar_path(id: 123456789)
    assert_response :not_found
  end

  test "original blob and representation routes are not mounted" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/forged/image.png")
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rails/active_storage/representations/redirect/forged/variant/image.png")
    end
  end
end
