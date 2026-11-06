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

  test "unsupported legacy blob types are denied by the private download endpoint" do
    message = rooms(:one).messages.create!(user: users(:one), body: "Untrusted legacy upload")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
      filename: "unsafe.svg", content_type: "image/svg+xml"
    )
    attachment = ActiveStorage::Attachment.create!(name: "attachments", record: message, blob: blob)

    sign_in users(:one)
    get chat_attachment_path(attachment)
    assert_response :not_found
  end

  test "oversized internal Active Storage blob cannot be downloaded" do
    message = rooms(:one).messages.create!(user: users(:one), body: "Oversized legacy upload")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x" * (Message::MAX_ATTACHMENT_BYTES + 1)),
      filename: "large.txt", content_type: "text/plain"
    )
    attachment = ActiveStorage::Attachment.create!(name: "attachments", record: message, blob: blob)

    sign_in users(:one)
    get chat_attachment_path(attachment)
    assert_response :not_found
  end

  test "private member can play WebM VP8 by range but outsider is denied" do
    Tempfile.create(["video-range", ".webm"]) do |file|
      assert system("ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi",
        "-i", "testsrc2=size=160x90:rate=10:duration=1",
        "-an", "-c:v", "libvpx", "-deadline", "realtime",
        "-cpu-used", "8", "-b:v", "120k", "-y", file.path,
        out: File::NULL, err: File::NULL)
      room = Room.create_private_room([users(:one), users(:two)],
        "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
      message = room.messages.create!(user: users(:one), body: "Short silent video clip")
      message.attachments.attach(io: File.open(file.path, "rb"),
        filename: "clip-test.webm", content_type: "video/webm")
      attachment = message.attachments.first

      sign_in users(:one)
      get chat_attachment_poster_path(attachment)
      assert_response :success
      assert_equal "image/png", response.media_type
      assert response.body.b.start_with?("\x89PNG\r\n\x1A\n".b),
        "Video poster must be a genuinely decoded PNG frame"
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      assert_match(/private/, response.headers["Cache-Control"])

      # A second current private-room member can see the same video poster.
      sign_out users(:one)
      sign_in users(:two)
      get chat_attachment_poster_path(attachment)
      assert_response :success
      assert_equal "image/png", response.media_type

      # Even a cached poster must be hidden immediately after membership revocation.
      room.participants.find_by!(user: users(:two)).destroy!
      get chat_attachment_poster_path(attachment)
      assert_response :not_found

      sign_out users(:two)
      sign_in users(:one)
      get chat_attachment_path(attachment), headers: { "Range" => "bytes=0-99" }
      assert_response :partial_content
      assert_equal 100, response.body.bytesize
      assert_equal "video/webm", response.media_type
      assert_equal "bytes", response.headers["Accept-Ranges"]
      assert_equal "private, no-store", response.headers["Cache-Control"]

      sign_out users(:one)
      stranger = User.create!(email: "video-outsider@example.test", password: "secure-password-123")
      sign_in stranger
      get chat_attachment_path(attachment)
      assert_response :not_found
      get chat_attachment_poster_path(attachment)
      assert_response :not_found
    end
  end

  test "member can stream bounded WebM audio ranges, outsider cannot" do
    Tempfile.create(["voice-test", ".webm"]) do |f|
      assert system("ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi",
        "-i", "sine=frequency=440:duration=1", "-c:a", "libopus", "-b:a", "24k",
        "-y", f.path, out: File::NULL, err: File::NULL)
      room = Room.create_private_room([users(:one), users(:two)],
        "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
      message = room.messages.create!(user: users(:one), body: "Voice test")
      message.attachments.attach(io: File.open(f.path, "rb"),
        filename: "voice.webm", content_type: "audio/webm")
      attachment = message.attachments.first

      assert attachment.blob.open { |temp| VoiceWebmInspection.valid?(temp) },
        "Stored Opus container must survive Active Storage"
      assert_equal 100, attachment.blob.download_chunk(0..99).bytesize,
        "Active Storage backend must support HTTP byte ranges"

      sign_in users(:one)
      get chat_attachment_path(attachment), headers: { "Range" => "bytes=0-99" }
      assert_response :partial_content
      assert_equal 100, response.body.bytesize
      assert_match(/\Abytes 0-99\//, response.headers["Content-Range"])
      assert_equal "audio/webm", response.media_type
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "bytes", response.headers["Accept-Ranges"]

      sign_out users(:one)
      stranger = User.create!(email: "voice-outsider@example.test", password: "secure-pass-123")
      sign_in stranger
      get chat_attachment_path(attachment)
      assert_response :not_found
    end
  end

  test "spoofed WebM content never produces a poster" do
    room = rooms(:one)
    message = room.messages.create!(user: users(:one), body: "Spoofed file")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("not a real WebM video"), filename: "spoofed.webm",
      content_type: "video/webm"
    )
    attachment = ActiveStorage::Attachment.create!(
      name: "attachments", record: message, blob: blob
    )

    sign_in users(:one)
    get chat_attachment_poster_path(attachment)
    assert_response :not_found
    get chat_attachment_path(attachment)
    assert_response :not_found
  end

  test "guest cannot request a private video poster" do
    get chat_attachment_poster_path(id: 1234)
    assert_redirected_to new_user_session_path
  end

  test "guest is redirected to sign in" do
    get chat_attachment_path(id: 1234)
    assert_redirected_to new_user_session_path
  end
end
