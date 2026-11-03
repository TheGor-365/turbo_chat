require "test_helper"

class MessageAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "third party cannot read attached file in private room" do
    alice = users(:one)
    bob = users(:two)
    outsider = users(:admin)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: alice, body: "Private")
    message.attachments.attach(
      io: StringIO.new("Private attachment"), filename: "confidential.txt", content_type: "text/plain"
    )
    attachment = message.attachments.first
    path = room_message_attachment_path(room, message, attachment.id)

    sign_in outsider
    get path
    assert_response :not_found

    sign_out outsider
    sign_in alice
    get path
    assert_response :success
    assert_equal "Private attachment", response.body
  end
end
