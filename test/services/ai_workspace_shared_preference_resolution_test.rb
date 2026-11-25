require "test_helper"

class AiWorkspaceSharedPreferenceResolutionTest < ActiveSupport::TestCase
  test "shared defaults inherit without copying and personal rows survive owner edits" do
    owner, member = users(:one), users(:two)
    room = Room.create!(name: "Shared resolver test", kind: "private_group", is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    room.participants.create!(user: member, group_role: "member")
    attrs = { profile_id: "universal", writing_style: "polish_clarity", language: "en", tone: "neutral" }
    resolver = AiWorkspace::WritingPreferenceResolver
    service = AiWorkspace::SharedWritingPreferences
    AiAccountWritingPreference.create!(user: member, **attrs.merge(language: "es"))
    assert_equal "account", resolver.for(user: member, room: room).source
    service.write(room: room, actor: owner, attributes: attrs, expected_revision: 0)
    assert_no_difference "AiRoomWritingPreference.count" do
      result = resolver.for(user: member, room: room)
      assert_equal "shared", result.source
      assert_equal "en", result.experience.settings[:language]
      assert_equal 1, result.shared_revision
    end
    personal = AiRoomWritingPreference.create!(user: member, room: room, **attrs.merge(language: "ru"))
    service.write(room: room, actor: owner, attributes: attrs.merge(language: "hy"), expected_revision: 1)
    assert_equal "ru", resolver.for(user: member, room: room).effective[:language]
    assert_equal "hy", resolver.for(user: owner, room: room).effective[:language]
    personal.destroy!
    assert_equal "hy", resolver.for(user: member, room: room).effective[:language]
    room.participants.where(user: member).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) { resolver.for(user: member, room: room) }
  end
end
