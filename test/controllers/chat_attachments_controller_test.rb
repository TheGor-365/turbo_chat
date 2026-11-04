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
      if response.server_error?
        warn "VOICE_RANGE_DEBUG readable_error=#{CGI.unescapeHTML(response.body.to_s.gsub(/<[^>]*>/, " ").gsub(/\s+/, " ")).byteslice(0, 2500)}"
        log_path = Rails.root.join("log/test.log")
        warn "VOICE_RANGE_DEBUG exception_candidates=#{response.body.scan(/(?:NoMethodError|NameError|ArgumentError|undefined method|TypeError|Error:)[^<]{0,160}/).first(10).inspect}"
        warn "VOICE_RANGE_DEBUG Rails logs=#{File.readlines(log_path).last(65).join}" if File.exist?(log_path)
      end
      assert_response :partial_content
      assert_equal 100, response.body.bytesize
      assert_match(/Abytes 0-99\//, response.headers["Content-Range"])
      assert_equal "audio/webm", response.media_type
      assert_equal "private, no-store", response.headers["Cache-Control"]

      sign_out users(:one)
      stranger = User.create!(email: "voice-outsider@example.test", password: "secure-pass-123")
      sign_in stranger
      get chat_attachment_path(attachment)
      assert_response :not_found
    end
  end

  test "guest is redirected to sign in" do
    get chat_attachment_path(id: 1234)
    assert_redirected_to new_user_session_path
  end
end
