require "test_helper"

class ConversationReadStateTest < ActiveSupport::TestCase
  test "does not create a read state for a user without room membership" do
    state = ConversationReadState.new(room: rooms(:one), user: users(:two))
    assert_not state.valid?
    assert_includes state.errors[:room], "is not accessible"
  end

  test "rejects using a message belonging to another room" do
    state = ConversationReadState.create!(room: rooms(:one), user: users(:one))
    assert_raises(ArgumentError) { state.advance_to!(messages(:two)) }
    assert_equal 0, state.reload.last_read_message_id
  end
end
