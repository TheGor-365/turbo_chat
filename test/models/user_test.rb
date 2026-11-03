require "test_helper"
require "stringio"

class UserTest < ActiveSupport::TestCase
  test "rejects uploaded avatar with unsupported content type" do
    user = users(:one)
    user.avatar.attach(io: StringIO.new("not an image"), filename: "payload.html", content_type: "text/html")
    assert_not user.valid?
    assert user.errors[:avatar].any?
  end

  test "rejects uploaded avatar larger than five megabytes" do
    user = users(:one)
    user.avatar.attach(io: StringIO.new("x" * (5.megabytes + 1)), filename: "large.jpg", content_type: "image/jpeg")
    assert_not user.valid?
    assert user.errors[:avatar].any?
  end
end
