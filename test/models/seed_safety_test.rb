require "test_helper"

class SeedSafetyTest < ActiveSupport::TestCase
  test "loading seeds does not silently create known admin accounts or rooms" do
    assert_no_difference ["User.count", "Room.count"] do
      load Rails.root.join("db/seeds.rb")
    end

    assert_not User.exists?(email: "gor@gor.com")
    assert_not User.exists?(email: "eric@eric.com")
  end
end
