require "test_helper"

class AiWorkspaceSharedWritingPreferencesTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "defaults-owner@example.test", password: "password123")
    @member = User.create!(email: "defaults-member@example.test", password: "password123")
    @outsider = User.create!(email: "defaults-outsider@example.test", password: "password123")
    @room = Room.create!(name: "Shared service test", kind: "private_group", is_private: true, owner: @owner)
    @room.participants.create!(user: @owner, group_role: "owner")
    @room.participants.create!(user: @member, group_role: "member")
    @service = AiWorkspace::SharedWritingPreferences
    @attributes = { profile_id: "universal", writing_style: "polish_clarity", language: "en", tone: "neutral" }
  end

  test "member reads without creating and owner writes with revision checks" do
    assert_no_difference "AiRoomSharedWritingPreference.count" do
      assert_equal 0, @service.read(room: @room, actor: @member)[:revision]
    end
    result = write(@owner, 0)
    assert_equal 1, result[:revision]
    assert_equal @owner.id, result[:editor][:id]
    assert_not @service.read(room: @room, actor: @member)[:editable]
    assert_equal 2, write(@owner, 1, @attributes.merge(language: "hy"))[:revision]
    assert_raises(AiWorkspace::SharedWritingPreferences::Conflict) { write(@owner, 1) }
    assert_equal "hy", @service.read(room: @room, actor: @member)[:preference][:language]
  end

  test "nonowner outsider and departed owner cannot write" do
    [@member, @outsider].each do |actor|
      assert_raises(AiWorkspace::Errors::Unauthorized) { write(actor, 0) }
    end
    assert_raises(AiWorkspace::Errors::Unauthorized) { @service.read(room: @room, actor: @outsider) }
    @room.participants.where(user: @owner).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) { write(@owner, 0) }
    assert_equal 0, @service.read(room: @room, actor: @member)[:revision]
  end

  test "unknown fields invalid values and revision types rejected without persistence" do
    assert_no_difference "AiRoomSharedWritingPreference.count" do
      assert_raises(AiWorkspace::Errors::InvalidPreset) { write(@owner, 0, @attributes.merge(editor_id: @outsider.id)) }
      assert_raises(AiWorkspace::Errors::InvalidPreset) { write(@owner, 0, @attributes.merge(language: "xx")) }
      assert_raises(AiWorkspace::Errors::InvalidPreset) { write(@owner, "0") }
    end
  end

  private

  def write(actor, revision, attributes = @attributes)
    @service.write(room: @room, actor: actor, attributes: attributes, expected_revision: revision)
  end
end
