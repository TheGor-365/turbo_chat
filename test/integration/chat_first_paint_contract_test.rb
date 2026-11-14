require "test_helper"

class ChatFirstPaintContractTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "authorized room starts history in a pending state but preserves message and composer" do
    room = rooms(:one)
    sign_in users(:one)
    get room_path(room)
    assert_response :success
    assert_select "#messages[data-scroll-target=scroller][data-scroll-phase=pending]", count: 1
    assert_select "#messages-container", count: 1
    assert_select "#chat-text", count: 1
    assert_select "#single_room[data-controller*=scroll]", count: 1
  end
end
