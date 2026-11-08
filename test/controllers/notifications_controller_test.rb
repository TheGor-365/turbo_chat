require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def direct_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "notification center requires login, stays scoped and never renders DM message body" do
    alice, bob = users(:one), users(:two)
    own_room = direct_room(alice, bob)
    incoming = own_room.messages.create!(user: bob, body: "Private Secret Do Not Render 977")
    note = Notification.find_by!(user: alice, message: incoming)

    stranger = User.create!(email: "notification-peer@example.test", password: "secure-password-123")
    forbidden = direct_room(bob, stranger)
    hidden = forbidden.messages.create!(user: bob, body: "Unrelated Secret Body 188")
    foreign_note = Notification.find_by!(user: stranger, message: hidden)

    get notifications_path
    assert_redirected_to new_user_session_path

    sign_in alice
    get notifications_path
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "#notification-list [data-notification-id='#{note.id}']", count: 1
    assert_select "#notification-list [data-notification-id='#{foreign_note.id}']", count: 0
    assert_select "a[href=?]", room_path(own_room, focus: incoming.id), text: "Open"
    assert_not_includes response.body, incoming.body
    assert_not_includes response.body, hidden.body
    assert_not_includes response.body, stranger.email
  end

  test "activity page explains empty event feed and links to authorized chat history" do
    alice = User.create!(email: "history-alice@example.test", password: "secure-password-123")
    bob = users(:two)
    stranger = users(:one)
    direct = direct_room(alice, bob)
    hidden = direct_room(stranger, bob)
    lounge = Room.create!(name: "history-public-lounge")
    lounge.joinables.create!(user: alice)
    inaccessible = Room.create!(name: "history-other-public")
    inaccessible.joinables.create!(user: stranger)
    direct.messages.create!(user: alice, body: "My past message is not a notification")

    sign_in alice
    get notifications_path
    assert_response :success
    assert_select "#activity-empty", text: /No activity events recorded/, count: 1
    assert_select "#notification-list", count: 0
    assert_select "#conversation-history a[href=?]", room_path(direct), count: 1
    assert_select "#conversation-history a[href=?]", room_path(lounge), count: 1
    assert_select "#conversation-history a[href=?]", room_path(hidden), count: 0
    assert_select "#conversation-history a[href=?]", room_path(inaccessible), count: 0
    assert_not_includes response.body, "My past message is not a notification"
    assert_not_includes response.body, bob.email
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "recipient can mark one event read without modifying conversation cursor" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: bob, body: "First new event")
    second = room.messages.create!(user: bob, body: "Second new event")
    first_note = Notification.find_by!(user: alice, message: first)
    second_note = Notification.find_by!(user: alice, message: second)
    sign_in alice

    post read_notification_path(first_note)
    assert_redirected_to notifications_path
    assert_not_nil first_note.reload.read_at
    assert_nil second_note.reload.read_at
    assert_nil ConversationReadState.find_by(user: alice, room: room)

    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count='1']", count: 1
    post read_all_notifications_path
    assert_redirected_to notifications_path
    assert_not_nil second_note.reload.read_at
    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count]", count: 0
  end

  test "room read cursor acknowledges only older matching personal events" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    older = room.messages.create!(user: bob, body: "Read this event")
    newer = room.messages.create!(user: bob, body: "Not yet acknowledged")
    sign_in alice

    post read_room_path(room), params: { last_read_message_id: older.id }
    assert_response :no_content
    assert_not_nil Notification.find_by!(user: alice, message: older).read_at
    assert_nil Notification.find_by!(user: alice, message: newer).read_at
    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count='1']"
  end

  test "foreign notification ids and former room members cannot mark items read" do
    alice, bob = users(:one), users(:two)
    stranger = User.create!(email: "notification-other@example.test", password: "secure-password-123")
    private_room = direct_room(bob, stranger)
    foreign = private_room.messages.create!(user: bob, body: "Foreign message")
    foreign_note = Notification.find_by!(user: stranger, message: foreign)

    own_room = direct_room(alice, bob)
    incoming = own_room.messages.create!(user: bob, body: "Previously visible")
    own_note = Notification.find_by!(user: alice, message: incoming)

    sign_in alice
    post read_notification_path(foreign_note), params: { user_id: stranger.id }
    assert_response :not_found
    assert_nil foreign_note.reload.read_at

    own_room.participants.where(user: alice).delete_all
    get notifications_path
    assert_response :success
    assert_select "[data-notification-id='#{own_note.id}']", count: 0
    post read_notification_path(own_note)
    assert_response :not_found
    assert_nil own_note.reload.read_at
    post read_all_notifications_path
    assert_redirected_to notifications_path
    assert_nil own_note.reload.read_at
  end


  test "cross-conversation search returns only presently authorized messages and supports context links" do
    alice, bob = users(:one), users(:two)
    outsider = User.create!(email: "archive-search-outsider@example.test",
      password: "secure-password-123")
    own_room = direct_room(alice, bob)
    allowed = own_room.messages.create!(user: bob, body: "Release milestone Orion-462")
    foreign_room = direct_room(bob, outsider)
    forbidden = foreign_room.messages.create!(user: bob, body: "Release milestone Orion-462 hidden")
    public_room = Room.create!(name: "archive-public-lounge")
    public_room.joinables.create!(user: bob)
    unjoined = public_room.messages.create!(user: bob, body: "Release milestone Orion-462 public")
    group = Room.create!(name: "archive-private-group", kind: "private_group",
      is_private: true, owner: bob)
    group.participants.create!(user: bob, group_role: "owner")
    private_hidden = group.messages.create!(user: bob, body: "Release milestone Orion-462 group")
    sign_in alice

    get notifications_path, params: { q: "Orion-462" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{allowed.id}']", count: 1
    assert_select "#archive-results a[href=?][aria-label='Open message in context']",
      room_path(own_room, focus: allowed.id), count: 1
    [forbidden, unjoined, private_hidden].each do |message|
      assert_select "#archive-results [data-archive-message-id='#{message.id}']", count: 0
      assert_not_includes response.body, message.body
    end
    assert_not_includes response.body, outsider.email
    assert_equal "private, no-store", response.headers["Cache-Control"]

    # Specifying an unauthorized room ID does not bypass the membership guard.
    get notifications_path, params: { q: "Orion-462", room_id: foreign_room.id }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id]", count: 0

    # Membership changes revoke access to already searchable history.
    own_room.participants.where(user: alice).delete_all
    get notifications_path, params: { q: "Orion-462" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{allowed.id}']", count: 0
    assert_not_includes response.body, allowed.body
  end

  test "archive searches filenames, image and document MIME types without public blobs" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    file_message = room.messages.create!(user: bob, body: "Shared architecture notes")
    file_message.attachments.attach(io: StringIO.new("Private architecture notes"),
      filename: "project-roadmap.txt", content_type: "text/plain")
    photo_message = room.messages.create!(user: bob, body: "Sample image")
    photo_message.attachments.attach(io: StringIO.new("binary test image"),
      filename: "gallery-sample.png", content_type: "image/png")
    outsider = User.create!(email: "archive-files-outsider@example.test",
      password: "secure-password-123")
    hidden_room = direct_room(bob, outsider)
    hidden = hidden_room.messages.create!(user: bob, body: "Not yours")
    hidden.attachments.attach(io: StringIO.new("secret file"), filename: "project-roadmap-secret.txt",
      content_type: "text/plain")
    sign_in alice

    get notifications_path, params: { q: "roadmap", kind: "documents" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{file_message.id}']", count: 1
    assert_select "#archive-results a[href=?]", chat_attachment_path(file_message.attachments.first), count: 1
    assert_select "#archive-results [data-archive-message-id='#{photo_message.id}']", count: 0
    assert_select "#archive-results [data-archive-message-id='#{hidden.id}']", count: 0
    assert_not_includes response.body, "project-roadmap-secret.txt"

    get notifications_path, params: { kind: "images" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{photo_message.id}']", count: 1
    assert_select "#archive-results img[src=?]", chat_attachment_path(photo_message.attachments.first), count: 1
    assert_select "#archive-results [data-archive-message-id='#{file_message.id}']", count: 0

    get notifications_path, params: { kind: "audio" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id]", count: 0
  end

  test "email mentions query only chat text and never indexes login emails" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    with_mail = room.messages.create!(user: bob, body: "Contact helpdesk@example.test for the draft.")
    normal = room.messages.create!(user: bob, body: "No email here")
    sign_in alice

    get notifications_path, params: { kind: "emails" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{with_mail.id}']", count: 1
    assert_select "#archive-results [data-archive-message-id='#{normal.id}']", count: 0
    assert_includes response.body, "external email inboxes are not connected"
    assert_not_includes response.body, bob.email

    get notifications_path, params: { q: bob.email }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id]", count: 0
  end

  test "archive filters periods and one authorized room, without wildcard broadening" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    old = room.messages.create!(user: bob, body: "Period-77 old memory")
    old.update_columns(created_at: 4.months.ago, updated_at: 4.months.ago)
    fresh = room.messages.create!(user: bob, body: "Period-77 fresh memory")
    second_room = Room.create!(name: "period-second-public")
    second_room.joinables.create!(user: alice)
    other = second_room.messages.create!(user: alice, body: "Period-77 second conversation")
    sign_in alice

    get notifications_path, params: { q: "Period-77", period: "month", room_id: room.id }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id='#{fresh.id}']", count: 1
    assert_select "#archive-results [data-archive-message-id='#{old.id}']", count: 0
    assert_select "#archive-results [data-archive-message-id='#{other.id}']", count: 0

    get notifications_path, params: { q: "Period-77" }
    assert_select "#archive-results [data-archive-message-id]", count: 3

    get notifications_path, params: { q: "%_" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id]", count: 0
  end

  test "archive ignores malformed filters, rejects oversized terms and requires authentication" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    room.messages.create!(user: bob, body: "searchable needle")
    get notifications_path, params: { q: "needle" }
    assert_redirected_to new_user_session_path

    sign_in alice
    get notifications_path, params: { q: "needle", kind: "unknown", period: "year",
      room_id: "-1" }
    assert_response :success
    assert_select "#archive-results [data-archive-message-id]", count: 1
    assert_select "nav.sd-archive-kinds a.is-active", text: /All/

    get notifications_path, params: { q: "n" }
    assert_response :success
    assert_select ".sd-archive-search-error", text: /at least two characters/
    assert_not_includes response.body, "searchable needle"

    get notifications_path, params: { q: "x" * 101 }
    assert_response :success
    assert_select ".sd-archive-search-error", text: /100 characters/
  end

  test "live inbox payload carries count only for the current recipient" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    room.messages.create!(user: bob, body: "Secret body for notification")
    sign_in alice

    get inbox_rooms_path
    assert_response :success
    json = JSON.parse(response.body)
    assert_includes json.fetch("notifications"), "Notifications"
    assert_includes json.fetch("notifications"), 'data-notification-unread-count="1"'
    assert_not_includes json.fetch("notifications"), "Secret body for notification"
    assert_not_includes json.fetch("notifications"), bob.email

    sign_out alice
    sign_in bob
    get inbox_rooms_path
    assert_not_includes JSON.parse(response.body).fetch("notifications"), "data-notification-unread-count"
  end
end
