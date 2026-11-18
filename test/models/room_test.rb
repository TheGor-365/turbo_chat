require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "a direct conversation is idempotent and has exactly two participants" do
    alice, bob = users(:one), users(:two)
    name = "private_#{[alice.id, bob.id].sort.join('_')}"
    before_count = Room.count

    first = Room.create_private_room([bob, alice], name)
    second = Room.create_private_room([alice, bob], name)

    assert_equal first.id, second.id
    assert_equal before_count + 1, Room.count
    assert first.is_private?
    assert_equal [alice.id, bob.id].sort, first.participants.pluck(:user_id).sort
    assert_equal 2, first.participants.count
  end

  test "a public room cannot claim a direct message name" do
    room = Room.new(name: "private_1_2", is_private: false)
    assert_not room.valid?
    assert room.errors[:name].any?
  end

  test "cannot create a direct room under an unrelated identifier" do
    assert_raises(ArgumentError) do
      Room.create_private_room([users(:one), users(:two)], "other-name")
    end
  end

  test "a direct message cannot acquire a third participant silently" do
    alice, bob = users(:one), users(:two)
    name = "private_#{[alice.id, bob.id].sort.join('_')}"
    room = Room.create!(name: name, is_private: true)
    other = User.create!(email: "third-party@example.test", password: "secure-password-123")
    room.participants.create!(user: other)

    assert_raises(ActiveRecord::RecordInvalid) do
      Room.create_private_room([alice, bob], name)
    end
    assert_equal [other.id], room.participants.pluck(:user_id)
  end
end
