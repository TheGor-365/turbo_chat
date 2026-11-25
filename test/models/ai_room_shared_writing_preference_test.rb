require "test_helper"

class AiRoomSharedWritingPreferenceTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "shared-owner@example.test", password: "password123")
    @room = Room.create!(name: "Shared defaults test", kind: "private_group",
      is_private: true, owner: @owner)
    @attributes = { room: @room, editor: @owner, profile_id: "universal",
      writing_style: "polish_clarity", language: "en", tone: "neutral" }
  end

  test "one shared snapshot per room with optimistic revision" do
    preference = AiRoomSharedWritingPreference.create!(@attributes)
    assert_equal 1, preference.revision
    stale = AiRoomSharedWritingPreference.find(preference.id)
    preference.update!(language: "hy")
    assert_equal 2, preference.revision
    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(language: "ru") }
    assert_equal "hy", preference.reload.public_snapshot[:language]
    assert_not AiRoomSharedWritingPreference.new(@attributes).valid?
  end

  test "shared defaults do not overwrite personal room or account settings" do
    personal = AiRoomWritingPreference.create!(user: @owner, room: @room,
      profile_id: "universal", writing_style: "polish_clarity", language: "ru", tone: "neutral")
    account = AiAccountWritingPreference.create!(user: @owner,
      profile_id: "universal", writing_style: "polish_clarity", language: "es", tone: "neutral")
    preference = AiRoomSharedWritingPreference.create!(@attributes)
    preference.update!(language: "hy")
    assert_equal "ru", personal.reload.language
    assert_equal "es", account.reload.language
  end

  test "invalid settings and public room rejected" do
    assert_not AiRoomSharedWritingPreference.new(@attributes.merge(language: "xx")).valid?
    assert_not AiRoomSharedWritingPreference.new(@attributes.merge(profile_id: "business")).valid?
    public_room = Room.create!(name: "Public defaults test", kind: "public_room", is_private: false)
    assert_not AiRoomSharedWritingPreference.new(@attributes.merge(room: public_room)).valid?
  end
end
