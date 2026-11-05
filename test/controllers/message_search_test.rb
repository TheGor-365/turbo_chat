require "test_helper"

class MessageSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "only authorized room members can search private messages" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "secret-room-query-2026")
    outsider = User.create!(email: "search-outsider@example.test", password: "secure-password-123")

    get search_room_messages_path(room), params: { q: "secret-room-query" }
    assert_redirected_to new_user_session_path

    sign_in outsider
    get search_room_messages_path(room), params: { q: "secret-room-query" }
    assert_response :forbidden
    assert_not_includes response.body, "secret-room-query-2026"

    sign_out outsider
    sign_in alice
    get search_room_messages_path(room), params: { q: "SECRET-room-query" }
    assert_response :success
    assert_select "turbo-frame#message_search_results li", count: 1
    assert_select ".message-search-excerpt", text: /secret-room-query-2026/
    assert_select "mark.message-search-highlight", text: "secret-room-query"
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "search is isolated to a joined public room and escapes SQL LIKE wildcards" do
    room = rooms(:one)
    room.messages.create!(user: users(:one), body: "invoice 100% settled id_8")
    room.messages.create!(user: users(:one), body: "invoice 1000 settled idX8")
    rooms(:two).messages.create!(user: users(:two), body: "invoice 100% settled id_8")

    sign_in users(:one)
    get search_room_messages_path(room), params: { q: "100%" }
    assert_response :success
    assert_select ".message-search-result", count: 1
    assert_select ".message-search-excerpt", text: /100% settled/

    get search_room_messages_path(room), params: { q: "id_8" }
    assert_response :success
    assert_select ".message-search-result", count: 1

    get search_room_messages_path(rooms(:two)), params: { q: "100%" }
    assert_response :forbidden
  end

  test "search handles short terms and rejects overlong terms without querying" do
    sign_in users(:one)
    get search_room_messages_path(rooms(:one)), params: { q: "x" }
    assert_response :success
    assert_select "turbo-frame#message_search_results", text: /at least 2 characters/

    get search_room_messages_path(rooms(:one)), params: { q: "z" * 101 }
    assert_response :bad_request
  end

  test "result excerpts highlight the matched text without interpreting message HTML" do
    room = rooms(:one)
    room.messages.create!(user: users(:one), body: "Before <img src=x onerror=alert(1)> after")
    sign_in users(:one)

    get search_room_messages_path(room), params: { q: "<img" }
    assert_response :success
    assert_select ".message-search-result", count: 1
    assert_select "mark.message-search-highlight", text: "<img", count: 1
    assert_select "turbo-frame#message_search_results img", count: 0
    assert_select "a.message-search-hit[href*='focus=']", count: 1
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "search paginates within a room and keeps its query on subsequent pages" do
    room = rooms(:one)
    19.times { |i| room.messages.create!(user: users(:one), body: "parcel-search-#{i}") }
    sign_in users(:one)

    get search_room_messages_path(room), params: { q: "parcel-search" }
    assert_response :success
    assert_select ".message-search-result", count: 15
    assert_select "a", text: "Next", count: 1

    get search_room_messages_path(room), params: { q: "parcel-search", page: 2 }
    assert_response :success
    assert_select ".message-search-result", count: 4
    assert_select "a", text: "Previous", count: 1
  end

  test "search result links open old messages without granting cross-room access" do
    room = rooms(:one)
    older = room.messages.create!(user: users(:one), body: "old-needle-target-2026")
    22.times { |i| room.messages.create!(user: users(:one), body: "newer note #{i}") }
    other = rooms(:two).messages.create!(user: users(:two), body: "foreign target")

    sign_in users(:one)
    get room_path(room)
    assert_response :success
    assert_not_includes response.body, older.body

    get room_path(room, focus: older.id)
    assert_response :success
    assert_select "#message_#{older.id}", count: 1
    assert_select "a", text: "Return to latest messages", count: 1

    get room_path(room, focus: other.id)
    assert_response :not_found
    assert_not_includes response.body, other.body

    get room_path(room, focus: "bad-id")
    assert_response :bad_request
  end
end
