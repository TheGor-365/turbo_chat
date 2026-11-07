require "test_helper"

# Explicitly disable test transactions so each worker uses its own
# PostgreSQL connection and actually exercises a conflicting insert.
class ConcurrentDirectRoomTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "parallel requests create one complete direct conversation" do
    alice, bob = users(:one), users(:two)
    name = "private_#{[alice.id, bob.id].sort.join('_')}"
    assert_not Room.exists?(name: name)

    ready = Queue.new
    go = Queue.new
    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          Room.create_private_room([alice, bob], name).id
        end
      end
    end

    4.times { ready.pop }
    4.times { go << true }
    room_ids = threads.map(&:value)

    assert_equal 1, room_ids.uniq.size
    assert_equal 1, Room.where(name: name).count
    room = Room.find(room_ids.first)
    assert room.is_private?
    assert_equal [alice.id, bob.id].sort, room.participants.pluck(:user_id).sort
    assert_equal 2, room.participants.count
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    Room.where(name: name).destroy_all if name
  end
end
