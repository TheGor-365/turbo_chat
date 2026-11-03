require "test_helper"

class ChatAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "a non-member cannot fetch a room document" do
    sign_in users(:two)
    get chat_attachment_path(id: 1234)
    assert_response :not_found
  end

  test "guest is redirected to sign in" do
    get chat_attachment_path(id: 1234)
    assert_redirected_to new_user_session_path
  end
end
