require "test_helper"
require "stringio"

class ChatAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-in room member can access a stored file" do
    sign_in users(:one)
    message = rooms(:one).messages.create!(user: users(:one), body: "File")
    message.attachments.attach(io: StringIO.new("hello"), filename: "hello.txt", content_type: "text/plain")
    get chat_attachment_path(message.attachments.first)
    assert_response :success
    assert_equal "hello", response.body
  end

  test "another account cannot access a stored file" do
    message = rooms(:one).messages.create!(user: users(:one), body: "File")
    message.attachments.attach(io: StringIO.new("hello"), filename: "hello.txt", content_type: "text/plain")
    sign_in users(:two)
    get chat_attachment_path(message.attachments.first)
    assert_response :not_found
  end

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
