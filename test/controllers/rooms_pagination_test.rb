require "test_helper"

class RoomsPaginationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "older message page returns an authorized Turbo frame with the next pager" do
    room = rooms(:one)
    user = users(:one)
    now = Time.current

    Message.insert_all!(25.times.map do |index|
      {
        room_id: room.id, user_id: user.id,
        body: "Historical message #{index}",
        created_at: now + index.seconds, updated_at: now + index.seconds
      }
    end)

    sign_in user
    get room_path(room, page: 2), headers: { "Turbo-Frame" => "page_handler" }

    assert_response :success
    assert_select 'turbo-frame#page_handler'
    assert_select 'turbo-stream[action="prepend"][target="messages-container"]', count: 1
    assert_select 'turbo-stream[action="replace"][target="pager"]', count: 1
    assert_includes response.body, "Load more messages"
  end

  test "room pagination stays forbidden for a user without membership" do
    sign_in users(:two)
    get room_path(rooms(:one), page: 2), headers: { "Turbo-Frame" => "page_handler" }
    assert_response :forbidden
  end
end
