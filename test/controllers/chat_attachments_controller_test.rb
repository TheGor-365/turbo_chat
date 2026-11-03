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

  test "leaving a public room immediately revokes access to existing attachments" do
    message = rooms(:one).messages.create!(user: users(:one), body: "Previously visible")
    message.attachments.attach(io: StringIO.new("private after leave"), filename: "note.txt", content_type: "text/plain")
    attachment = message.attachments.first
    sign_in users(:one)

    get chat_attachment_path(attachment)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    delete leave_room_path(rooms(:one))
    assert_redirected_to rooms_path
    get chat_attachment_path(attachment)
    assert_response :not_found
  end

  test "a private conversation participant can fetch attachments but an outsider cannot" do
    room = Room.create!(name: "private-attachment-integration", is_private: true)
    room.participants.create!(user: users(:one))
    message = room.messages.create!(user: users(:one), body: "Private attachment")
    message.attachments.attach(io: StringIO.new("sensitive"), filename: "doc.txt", content_type: "text/plain")

    sign_in users(:one)
    get chat_attachment_path(message.attachments.first)
    assert_response :success
    assert_equal "sensitive", response.body

    sign_out users(:one)
    sign_in users(:two)
    get chat_attachment_path(message.attachments.first)
    assert_response :not_found
  end

  test "guest is redirected to sign in" do
    get chat_attachment_path(id: 1234)
    assert_redirected_to new_user_session_path
  end
end
