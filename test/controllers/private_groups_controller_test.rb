require "test_helper"

class PrivateGroupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def build_group(owner:, name: "Planning circle")
    Room.transaction do
      room = Room.create!(name: name, kind: "private_group", is_private: true, owner: owner)
      room.participants.create!(user: owner, group_role: "owner")
      room
    end
  end

  test "any signed in user can create an isolated private group without modifying a DM" do
    alice, bob = users(:one), users(:two)
    dm = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice

    assert_difference("Room.count", 1) do
      post private_groups_path, params: { private_group: {
        name: "  Planning   circle ", is_private: false, owner_id: bob.id, kind: "public_room"
      } }
    end
    room = Room.find_by!(name: "Planning circle")
    assert_response :see_other
    assert_redirected_to room_path(room)
    assert room.private_group?
    assert room.is_private?
    assert_equal alice, room.owner
    assert_equal [alice.id], room.participants.pluck(:user_id)
    assert room.accessible_to?(alice)
    assert_not room.accessible_to?(bob)
    assert dm.direct_message?
    assert_equal [alice.id, bob.id].sort, dm.participants.pluck(:user_id).sort
    assert_select "body", count: 0 # POST must redirect, not render private group HTML
  end

  test "nonmembers cannot access group chat, sync, search or realtime while invitation pending" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Hidden workgroup")
    message = group.messages.create!(user: alice, body: "Secret unread from private group")
    sign_in bob

    get room_path(group)
    assert_response :forbidden
    get sync_room_messages_path(group), params: { after_id: 0 }
    assert_response :forbidden
    get search_room_messages_path(group), params: { q: "Secret" }
    assert_response :forbidden
    post room_messages_path(group), params: { message: { body: "Attempt" } }
    assert_response :forbidden
    post read_room_path(group), params: { last_read_message_id: message.id }
    assert_response :forbidden
    get presence_room_path(group)
    assert_response :forbidden

    get rooms_path
    assert_response :success
    assert_select "#public-room-directory", text: /Hidden workgroup/, count: 0
    assert_select "#direct-rooms", text: /Hidden workgroup/, count: 0
    assert_select "#private-group-rooms", text: /Hidden workgroup/, count: 0
    get inbox_rooms_path, as: :json
    snapshot = JSON.parse(response.body)
    assert_not_includes snapshot.fetch("public"), group.name
    assert_not_includes snapshot.fetch("direct"), group.name
    assert_not_includes snapshot.fetch("groups"), group.name
    get notifications_path
    assert_not_includes response.body, group.name
  end

  test "owner invites one recipient and only that recipient can accept" do
    alice, bob = users(:one), users(:two)
    outsider = User.create!(email: "invite-outsider@example.test", password: "secure-password-123")
    group = build_group(owner: alice, name: "Owner invitation room")
    sign_in alice

    post invite_private_group_path(group), params: { user_id: bob.id }
    assert_response :see_other
    invitation = PrivateGroupInvitation.find_by!(room: group, user: bob)
    assert_equal "pending", invitation.status
    assert_not group.accessible_to?(bob)
    sign_out alice

    sign_in outsider
    post accept_private_group_invitation_path(invitation)
    assert_response :not_found
    post decline_private_group_invitation_path(invitation)
    assert_response :not_found
    post invite_private_group_path(group), params: { user_id: outsider.id }
    assert_response :not_found
    assert_not group.accessible_to?(outsider)
    sign_out outsider

    group.messages.create!(user: alice, body: "Private message sent before acceptance")
    sign_in bob
    get rooms_path
    assert_select "#private-group-invitations [data-group-invitation-id='#{invitation.id}']", count: 1
    assert_select "#private-group-rooms", text: /Owner invitation room/, count: 0
    post accept_private_group_invitation_path(invitation)
    assert_response :see_other
    assert_redirected_to room_path(group)
    assert_equal "accepted", invitation.reload.status
    assert group.accessible_to?(bob)
    assert_equal "member", group.participants.find_by!(user: bob).group_role
    assert_equal group.messages.maximum(:id),
      ConversationReadState.find_by!(room: group, user: bob).last_read_message_id
    get room_path(group)
    assert_response :success
    get inbox_rooms_path
    assert_includes JSON.parse(response.body).fetch("groups"), group.name
    assert_not_includes JSON.parse(response.body).fetch("direct"), group.name
    get notifications_path
    assert_select "#conversation-history a[href=?]", room_path(group), count: 1
  end

  test "invitee can decline and owner can re-invite without granting history" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Declined private group")
    sign_in alice
    post invite_private_group_path(group), params: { user_id: bob.id }
    invite = PrivateGroupInvitation.find_by!(room: group, user: bob)
    sign_out alice

    sign_in bob
    post decline_private_group_invitation_path(invite)
    assert_response :see_other
    assert_equal "declined", invite.reload.status
    assert_not group.accessible_to?(bob)
    sign_out bob

    sign_in alice
    post invite_private_group_path(group), params: { user_id: bob.id }
    assert_response :see_other
    assert_equal "pending", invite.reload.status
    assert_equal 1, PrivateGroupInvitation.where(room: group, user: bob).count
  end

  test "private group attachments remain inaccessible until accepted and after revocation" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Protected shared attachment")
    message = group.messages.create!(user: alice, body: "Sensitive internal attachment")
    message.attachments.attach(
      io: StringIO.new("PRIVATE GROUP ATTACHMENT BYTES"),
      filename: "group-note.txt",
      content_type: "text/plain"
    )
    attachment = message.attachments.first
    sign_in bob

    get chat_attachment_path(attachment)
    assert_response :not_found
    sign_out bob

    group.participants.create!(user: bob, group_role: "member")
    sign_in bob
    get chat_attachment_path(attachment)
    assert_response :success
    assert_includes response.body, "PRIVATE GROUP ATTACHMENT BYTES"
    sign_out bob

    group.participants.where(user: bob).delete_all
    sign_in bob
    get chat_attachment_path(attachment)
    assert_response :not_found
    get room_path(group)
    assert_response :forbidden
  end


  test "group member leaves via the public-style control without deleting history" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Member leave group")
    group.participants.create!(user: bob, group_role: "member")
    message = group.messages.create!(user: alice, body: "Preserved history")
    sign_in bob

    get room_path(group)
    assert_response :success
    assert_select "#private-group-rooms form[action=?] button[aria-label=?]",
      leave_private_group_path(group), "Leave #{group.name}", count: 1
    assert_select "#private-group-rooms .sd-room-entry__title", text: group.name

    assert_no_difference "Room.count" do
      assert_no_difference "Message.count" do
        delete leave_private_group_path(group)
      end
    end
    assert_response :see_other
    assert_redirected_to rooms_path
    assert_not group.accessible_to?(bob)
    assert group.accessible_to?(alice)
    assert_equal "Preserved history", message.reload.body
    get room_path(group)
    assert_response :forbidden
    get sync_room_messages_path(group), params: { after_id: 0 }
    assert_response :forbidden
    get inbox_rooms_path, as: :json
    assert_not_includes JSON.parse(response.body).fetch("groups"), group.name

    sign_out bob
    sign_in alice
    post invite_private_group_path(group), params: { user_id: bob.id }
    assert_response :see_other
    assert_equal "pending", PrivateGroupInvitation.find_by!(room: group, user: bob).status
  end

  test "owner leave transfers ownership and revokes pending third-party invites" do
    alice, bob = users(:one), users(:two)
    eve = User.create!(email: "pending-owner-transfer@example.test", password: "secure-password-123")
    group = build_group(owner: alice, name: "Transfer owner group")
    group.participants.create!(user: bob, group_role: "member")
    message = group.messages.create!(user: alice, body: "Ownership transfer preserves history")
    sign_in alice

    post invite_private_group_path(group), params: { user_id: eve.id }
    assert_response :see_other
    invitation = PrivateGroupInvitation.find_by!(room: group, user: eve)
    assert_equal "pending", invitation.status

    assert_no_difference "Room.count" do
      assert_no_difference "Message.count" do
        delete leave_private_group_path(group)
      end
    end
    assert_response :see_other
    assert_redirected_to rooms_path
    assert_equal bob.id, group.reload.owner_id
    assert_equal "owner", group.participants.find_by!(user: bob).group_role
    assert_not group.accessible_to?(alice)
    assert group.accessible_to?(bob)
    assert_equal "revoked", invitation.reload.status
    assert_equal "Ownership transfer preserves history", message.reload.body
    get room_path(group)
    assert_response :forbidden
    sign_out alice

    sign_in eve
    post accept_private_group_invitation_path(invitation)
    assert_response :not_found
    assert_not group.accessible_to?(eve)
    sign_out eve

    sign_in bob
    get room_path(group)
    assert_response :success
    post invite_private_group_path(group), params: { user_id: alice.id }
    assert_response :see_other
    assert_equal "pending", PrivateGroupInvitation.find_by!(room: group, user: alice).status
  end

  test "last owner stays when there is no member to transfer leadership to" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Owner alone group")
    sign_in bob
    delete leave_private_group_path(group)
    assert_response :not_found
    sign_out bob

    sign_in alice
    delete leave_private_group_path(group)
    assert_response :see_other
    assert_redirected_to room_path(group)
    assert_match(/Invite another member/, flash[:private_group_leave_error])
    assert group.reload.accessible_to?(alice)
    assert_equal alice.id, group.owner_id
    assert_equal ["owner"], group.participants.pluck(:group_role)
    get room_path(group)
    assert_response :success
    assert_select "#private-group-details .sd-group-leave-feedback[role=alert]",
      text: /Invite another member/
  end

  test "private leave action excludes public rooms and direct messages" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Leave membership guard group")
    dm = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice
    delete leave_private_group_path(rooms(:one))
    assert_response :not_found
    delete leave_private_group_path(dm)
    assert_response :not_found
    assert group.accessible_to?(alice)
    assert dm.accessible_to?(alice)
  end

  test "owner can revoke membership but member cannot remove the owner" do
    alice, bob = users(:one), users(:two)
    group = build_group(owner: alice, name: "Revocation group")
    group.participants.create!(user: bob, group_role: "member")
    group.messages.create!(user: bob, body: "Before revocation")

    sign_in bob
    delete remove_member_private_group_path(group, user_id: alice.id)
    assert_response :not_found
    sign_out bob

    sign_in alice
    delete remove_member_private_group_path(group, user_id: alice.id)
    assert_response :forbidden
    assert group.accessible_to?(alice)
    delete remove_member_private_group_path(group, user_id: bob.id)
    assert_response :see_other
    assert_not group.accessible_to?(bob)
    sign_out alice

    sign_in bob
    get room_path(group)
    assert_response :forbidden
    get sync_room_messages_path(group), params: { after_id: 0 }
    assert_response :forbidden
    get notifications_path
    assert_not_includes response.body, group.name
  end
end
