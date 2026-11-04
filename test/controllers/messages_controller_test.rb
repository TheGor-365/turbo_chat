require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  test "member may create a message and cannot spoof the author" do
    sign_in users(:one)
    assert_difference "Message.count", 1 do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Server owned identity", user_id: users(:two).id }
      }
    end
    assert_redirected_to room_path(rooms(:one))
    assert_equal users(:one).id, Message.order(:id).last.user_id
  end

  test "message bursts return 429 before persisting excess messages" do
    # Fixed-window throttles intentionally reset at minute boundaries.
    # Freeze time inside one window so this regression is not dependent
    # on the CI clock rolling from xx:59 to xx:00 mid-loop.
    travel_to Time.utc(2026, 11, 4, 10, 0, 30) do
      sign_in users(:one)
      30.times do |i|
        post room_messages_path(rooms(:one)), params: { message: { body: "rate test #{i}" } }
        assert_redirected_to room_path(rooms(:one))
      end

      assert_no_difference "Message.count" do
        post room_messages_path(rooms(:one)), params: { message: { body: "over limit" } }
      end
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
    end
  end

  test "member can upload an ordinary UTF-8 text attachment" do
    sign_in users(:one)
    assert_difference "Message.count", 1 do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Attached note", attachments: [fixture_file_upload("upload_note.txt", "text/plain")] }
      }
    end
    assert_redirected_to room_path(rooms(:one))
    assert_equal 1, Message.order(:id).last.attachments.count
  end

  test "rejects html bytes falsely claimed to be a PNG" do
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Unsafe upload", attachments: [fixture_file_upload("upload_spoofed.html", "image/png")] }
      }
    end
    assert_redirected_to room_path(rooms(:one))
    assert_match(/content does not match|type is not allowed/, flash[:alert])
  end

  test "rejects uninspected signed-blob direct uploads" do
    sign_in users(:one)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("some note"), filename: "note.txt", content_type: "text/plain"
    )
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Uninspected file", attachments: [blob.signed_id] }
      }
    end
    assert_redirected_to room_path(rooms(:one))
    assert_match(/Direct uploads are not supported/, flash[:alert])
  end

  test "third party cannot write to private room even by direct id" do
    room = Room.create!(name: "direct-id-private", is_private: true)
    room.participants.create!(user: users(:two))
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(room), params: { message: { body: "intrusion" } }
    end
    assert_response :forbidden
  end
end
