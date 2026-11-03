require "test_helper"

class ChatAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest is redirected to sign in" do
    get chat_attachment_path(id: 1234)
    assert_redirected_to new_user_session_path
  end
end
