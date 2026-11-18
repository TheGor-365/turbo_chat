# frozen_string_literal: true
require "test_helper"

class LocalizedRoomListTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "room rows, activity, presence and empty chat text localize in four languages" do
    user, peer = users(:one), users(:two)
    room = Room.create!(name: "public-room-list-translation")
    room.joinables.create!(user: user)
    sign_in user
    initial_members = room.joinables.count

    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale, people: peer.chat_label }
      assert_response :success
      assert_select "#notifications-nav .sd-inbox-tool-label", text: I18n.t("ui.room_list.activity", locale: locale)
      assert_select "#empty-conversation-title", text: I18n.t("ui.room_list.empty_chat_title", locale: locale)
      assert_select "#empty-conversation p", text: I18n.t("ui.room_list.empty_chat_hint", locale: locale)
      assert_select "#rooms .sd-room-type[title=?]", I18n.t("ui.room_list.public_room", locale: locale)
      assert_select "#rooms form[action=?] button[aria-label=?]",
        leave_room_path(room), I18n.t("ui.room_list.leave_named", locale: locale, name: room.name)
      assert_select "#users [aria-label=?]", I18n.t("ui.room_list.presence_unavailable", locale: locale)
      get inbox_rooms_path, as: :json
      snapshot = JSON.parse(response.body)
      assert_includes snapshot.fetch("public"), room.name
      assert_includes snapshot.fetch("notifications"), I18n.t("ui.room_list.activity", locale: locale)
    end
    assert_equal initial_members, room.joinables.reload.count
  end

  test "pending private invitation is localized and not accepted by viewing the inbox" do
    owner, invited = users(:one), users(:two)
    room = Room.create!(name: "private-invitation-localized", kind: "private_group", is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    invitation = PrivateGroupInvitation.create!(room: room, user: invited, invited_by: owner, status: "pending")
    sign_in invited

    %w[en ru hy es].each do |locale|
      get rooms_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "#private-group-invitations [data-group-invitation-id=?]", invitation.id.to_s
      assert_select "#private-group-invitations .sd-group-invitations[aria-label=?]",
        I18n.t("ui.room_list.invitations", locale: locale)
      assert_select "#private-group-invitations .sd-group-invitation span",
        text: I18n.t("ui.room_list.invited_by", locale: locale, name: owner.chat_label)
      assert_select "#private-group-invitations button[aria-label=?]",
        I18n.t("ui.room_list.accept_named", locale: locale, name: room.name)
      assert_equal "pending", invitation.reload.status
      assert_not room.accessible_to?(invited)
    end
  end
end
