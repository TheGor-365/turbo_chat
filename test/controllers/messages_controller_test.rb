require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers


  test "client proposal message shows safe formatting without rendering malicious HTML" do
    room = rooms(:one)
    raw = "**Client Proposal Outline**\n\n**Problem**\nPOST /orders returns HTTP 422. [M29][M30]\n\n**Work**\n- Inspect \x60Order\x60 validations\n- Review Strong Parameters\n\n<script>alert(1)</script>"
    message = room.messages.create!(user: users(:one), body: raw)
    sign_in users(:one)

    get room_path(room)
    assert_response :success
    assert_select "#message_#{message.id} .sd-message-rich strong", text: "Client Proposal Outline"
    assert_select "#message_#{message.id} .sd-message-rich ul li", count: 2
    assert_select "#message_#{message.id} .sd-message-rich code", text: "Order"
    assert_select "#message_#{message.id} .sd-message-source-ref", text: "[M29]"
    assert_select "#message_#{message.id} script", count: 0
    assert_select "#message_#{message.id} .sd-message-rich a", count: 0
    assert_includes response.body, "&lt;script&gt;"
    assert_equal raw, message.reload.body
  end

  test "authenticated room member can catch up after a cursor without full page reload" do
    room = rooms(:one)
    sign_in users(:one)
    previous = room.messages.create!(user: users(:one), body: "Before sync")
    newest = room.messages.create!(user: users(:one), body: "Missing from stale tab")

    get sync_room_messages_path(room), params: { after_id: previous.id },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal newest.id.to_s, response.headers["X-Chat-Last-Id"]
    assert_select 'turbo-stream[action="append"][target="messages-container"]'
    assert_includes response.body, "Missing from stale tab"
    assert_not_includes response.body, "Before sync"
  end

  test "HTTP sync reconciles missed edits and deletes only within the authorized room" do
    room = rooms(:one)
    alice = users(:one)
    edited = room.messages.create!(user: alice, body: "Before sync revision")
    removed = room.messages.create!(user: alice, body: "Deleted while socket was down")
    unchanged = room.messages.create!(user: alice, body: "Do not rerender unchanged")

    original_edited = (edited.updated_at.to_r * 1_000_000).to_i
    original_removed = (removed.updated_at.to_r * 1_000_000).to_i
    original_unchanged = (unchanged.updated_at.to_r * 1_000_000).to_i
    edited.update!(body: "Edited while disconnected", updated_at: edited.updated_at + 1.second)
    removed.destroy!

    sign_in alice
    get sync_room_messages_path(room), params: {
      after_id: unchanged.id,
      recheck: "#{edited.id}:#{original_edited},#{removed.id}:#{original_removed},#{unchanged.id}:#{original_unchanged}"
    }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "message_#{edited.id}", count: 1
    assert_select "turbo-stream[action=remove][target=?]", "message_#{removed.id}", count: 1
    assert_select "turbo-stream[action=replace][target=?]", "message_#{unchanged.id}", count: 0
    assert_select "turbo-stream[action=append][target=messages-container]", count: 1
    assert_includes response.body, "Edited while disconnected"
    assert_not_includes response.body, "Before sync revision"
    assert_not_includes response.body, "Do not rerender unchanged"
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "HTTP recheck caps input and never reveals messages from another room" do
    room = rooms(:one)
    alien = rooms(:two).messages.create!(user: users(:two), body: "Secret from another room")
    version = (alien.updated_at.to_r * 1_000_000).to_i
    sign_in users(:one)

    get sync_room_messages_path(room), params: { after_id: alien.id, recheck: "#{alien.id}:#{version}" }
    assert_response :success
    assert_select "turbo-stream[action=remove][target=?]", "message_#{alien.id}", count: 1
    assert_not_includes response.body, alien.body

    invalid = [
      "-1:#{version}", "1:0", "1:#{version},1:#{version}",
      "1:#{version}," * 30 + "1:#{version}",
      "1:#{version};2:#{version}",
      "x" * 1_201
    ]
    invalid.each do |recheck|
      get sync_room_messages_path(room), params: { after_id: 0, recheck: recheck }
      assert_response :bad_request
    end
  end


  test "HTTP recovery notices reaction additions and removal of older reaction" do
    room = rooms(:one)
    alice, bob = users(:one), users(:two)
    room.joinables.find_or_create_by!(user: bob)
    message = room.messages.create!(user: alice, body: "Reaction sync")
    before_reaction = (message.updated_at.to_r * 1_000_000).to_i
    now = Time.current

    first = nil
    travel_to(now + 1.minute) { first = message.message_reactions.create!(user: alice, emoji: "👍") }
    after_first = (message.reload.updated_at.to_r * 1_000_000).to_i
    assert_operator after_first, :>, before_reaction
    sign_in alice
    get sync_room_messages_path(room), params: {
      after_id: message.id, recheck: "#{message.id}:#{before_reaction}"
    }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "message_#{message.id}", count: 1
    assert_includes response.body, "Remove 👍 reaction"

    travel_to(now + 2.minutes) { message.message_reactions.create!(user: bob, emoji: "🔥") }
    with_both = (message.reload.updated_at.to_r * 1_000_000).to_i
    assert_operator with_both, :>, after_first
    # max(reactions.created_at) alone would not advance when removing the older reaction.
    travel_to(now + 3.minutes) { first.destroy! }
    after_removal = (message.reload.updated_at.to_r * 1_000_000).to_i
    assert_operator after_removal, :>, with_both
    get sync_room_messages_path(room), params: {
      after_id: message.id, recheck: "#{message.id}:#{with_both}"
    }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "message_#{message.id}", count: 1
    assert_includes response.body, "React 🔥"
    assert_not_includes response.body, "Remove 👍 reaction"
  end

  test "private-room sync refuses unrelated users and guests" do
    room = Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    room.messages.create!(user: users(:one), body: "Secret for members")
    outsider = User.create!(email: "outsider-sync@example.test", password: "secure-password-123")

    get sync_room_messages_path(room), params: { after_id: 0 }
    assert_redirected_to new_user_session_path

    sign_in outsider
    get sync_room_messages_path(room), params: { after_id: 0 }
    assert_response :forbidden
    assert_not_includes response.body, "Secret for members"
  end

  test "message-sync cursor rejects malformed values" do
    sign_in users(:one)
    get sync_room_messages_path(rooms(:one)), params: { after_id: "-123" }
    assert_response :bad_request
  end

  test "member replies to an authorized message in the same room" do
    room = rooms(:one)
    parent = room.messages.create!(user: users(:one), body: "Quote me")
    sign_in users(:one)
    assert_difference "Message.count", 1 do
      post room_messages_path(room), params: {
        message: { body: "My reply", reply_to_id: parent.id }
      }
    end
    assert_redirected_to room_path(room)
    assert_equal parent.id, Message.order(:id).last.reply_to_id
  end

  test "reply quote links to an authorized focus window, not an unloaded fragment" do
    alice = users(:one)
    room = rooms(:one)
    original = room.messages.create!(user: alice, body: "Context far back in history")
    12.times { |i| room.messages.create!(user: alice, body: "Intermediate message #{i}") }
    reply = room.messages.create!(user: alice, body: "Later reply", reply_to: original)
    sign_in alice

    get room_path(room)
    assert_response :success
    assert_select "#message_#{reply.id} a.message-quote-link[href=?]",
      room_path(room, focus: original.id), text: /Context far back in history/
    assert_select "#message_#{original.id}", count: 0

    get room_path(room, focus: original.id)
    assert_response :success
    assert_select "#message_#{original.id}", count: 1
    assert_select ".message-focus-banner", text: /Viewing an older message/
  end

  test "outsider cannot use a reply focus URL to view another pair's private messages" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    original = room.messages.create!(user: alice, body: "Private quote target")
    outsider = User.create!(email: "quote-outsider@example.test", password: "secure-password-123")
    sign_in outsider

    get room_path(room, focus: original.id)
    assert_response :forbidden
    assert_not_includes response.body, original.body
  end

  test "reply target from a different room is rejected without exposing it" do
    parent = rooms(:two).messages.create!(user: users(:two), body: "Secret room content")
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Try cross-room reply", reply_to_id: parent.id }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_entity
    assert_not_includes response.body, parent.body
  end

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

  test "member can upload and privately download a Markdown document" do
    sign_in users(:one)
    assert_difference "Message.count", 1 do
      post room_messages_path(rooms(:one)), params: {
        message: {
          body: "Private Markdown document",
          attachments: [fixture_file_upload("upload_note.md", "text/plain")]
        }
      }
    end

    assert_redirected_to room_path(rooms(:one))
    message = Message.order(:id).last
    assert_equal 1, message.attachments.count
    attachment = message.attachments.first
    assert_includes Message::ALLOWED_CONTENT_TYPES, attachment.blob.content_type
    assert_equal "upload_note.md", attachment.filename.to_s

    get chat_attachment_path(attachment)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_match(/attachment/i, response.headers["Content-Disposition"])
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

  test "Turbo rejection returns the exact safe attachment validation reason" do
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "Unsent draft", attachments: [fixture_file_upload("upload_spoofed.html", "image/png")] }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_entity
    assert_match(/Attachment content does not match its declared type/, response.body)
    assert_includes response.body, "upload_spoofed.html"
    assert_match(/text\/plain/i, response.media_type)
  end

  test "Turbo model rejection explains a blank message without leaking internal details" do
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:one)), params: {
        message: { body: "" }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_entity
    assert_match(/Message cannot be blank/, response.body)
    assert_match(/text\/plain/i, response.media_type)
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
