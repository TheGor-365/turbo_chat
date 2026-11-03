require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "private room names are reserved from public creation" do
    room = Room.new(name: "private_1_2", is_private: false)
    assert_not room.valid?
  end

  test "private rooms only authorize participants" do
    alice = users(:one)
    bob = users(:two)
    outsider = users(:admin)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    assert room.accessible_to?(alice)
    assert room.accessible_to?(bob)
    refute room.accessible_to?(outsider)
  end

  test "the same pair reuses one private conversation" do
    alice = users(:one)
    bob = users(:two)
    key = "private_#{[alice.id, bob.id].sort.join('_')}"
    first = Room.create_private_room([alice, bob], key)
    second = Room.create_private_room([bob, alice], key)
    assert_equal first.id, second.id
    assert_equal 2, first.participants.count
  end
end
