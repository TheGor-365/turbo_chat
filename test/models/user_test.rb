require "test_helper"
require "stringio"

class UserTest < ActiveSupport::TestCase
  test "optional profile name supports Cyrillic and Armenian and collapses spaces" do
    user = User.new(email: "profile-name@example.test", password: "testing-secure-password-123",
      display_name: "  Мария   Անահիտ  ")
    assert user.valid?, user.errors.full_messages.join(", ")
    assert_equal "Мария Անահիտ", user.display_name
    assert_equal "Мария Անահիտ", user.chat_label

    user.display_name = "   "
    assert user.valid?
    assert_nil user.display_name
  end

  test "public name rejects emails, markup, overlong and one-letter labels" do
    user = User.new(email: "bad-profile@example.test", password: "testing-secure-password-123")
    ["someone@example.test", "<script>", "x" * 49, "x", "Bob\u202Eadmin"].each do |invalid|
      user.display_name = invalid
      assert_not user.valid?, "Accepted invalid label: #{invalid.inspect}"
      assert user.errors[:display_name].present?
    end
  end

  test "existing accounts have non-email fallback labels" do
    user = users(:one)
    assert_nil user.display_name
    assert_equal "Member ##{user.id}", user.chat_label
    assert_not_equal user.email, user.chat_label
  end

  test "new users have no automatically attached personal portrait" do
    user = User.create!(email: "neutral-avatar@example.test", password: "testing-secure-password-123")

    assert_not user.avatar.attached?
  end
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
