require "test_helper"

class MessageReactionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @room = rooms(:one)
    @message = @room.messages.create!(user: users(:one), body: "Reaction endpoint")
  end

  test "member can react once and toggle their own reaction" do
    sign_in users(:one)
    assert_difference "MessageReaction.count", 1 do
      post room_message_reactions_path(@room, @message),
        params: { reaction: { emoji: "❤️", user_id: users(:two).id } }
    end
    assert_redirected_to room_path(@room)
    reaction = @message.message_reactions.sole
    assert_equal users(:one).id, reaction.user_id

    assert_no_difference "MessageReaction.count" do
      post room_message_reactions_path(@room, @message), params: { reaction: { emoji: "❤️" } }
    end
    assert_redirected_to room_path(@room)

    assert_difference "MessageReaction.count", -1 do
      delete room_message_reaction_path(@room, @message, reaction)
    end
    assert_redirected_to room_path(@room)
  end

  test "only supported emojis accepted" do
    sign_in users(:one)
    assert_no_difference "MessageReaction.count" do
      post room_message_reactions_path(@room, @message),
        params: { reaction: { emoji: "anything" } }
    end
    assert_response :unprocessable_entity
  end

  test "private nonmember and unauthenticated access are rejected" do
    private_room = Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    target = private_room.messages.create!(user: users(:one), body: "Secret message")
    outsider = User.create!(email: "reaction-outsider@example.test", password: "long-secret-123")

    post room_message_reactions_path(private_room, target), params: { reaction: { emoji: "👍" } }
    assert_redirected_to new_user_session_path

    sign_in outsider
    assert_no_difference "MessageReaction.count" do
      post room_message_reactions_path(private_room, target), params: { reaction: { emoji: "👍" } }
    end
    assert_response :forbidden
    assert_not_includes response.body, "Secret message"
  end

  test "cannot react through wrong room or delete another account's reaction" do
    @room.joinables.find_or_create_by!(user: users(:two))
    their_reaction = @message.message_reactions.create!(user: users(:two), emoji: "🔥")
    sign_in users(:one)

    assert_no_difference "MessageReaction.count" do
      delete room_message_reaction_path(@room, @message, their_reaction)
    end
    assert_response :not_found

    other_room = rooms(:two)
    assert_no_difference "MessageReaction.count" do
      assert_raises(ActiveRecord::RecordNotFound) do
        post room_message_reactions_path(other_room, @message),
          params: { reaction: { emoji: "❤️" } }
      end
    end
  end

  test "turbo stream reaction update includes a per-user selected button" do
    sign_in users(:one)
    post room_message_reactions_path(@room, @message),
      params: { reaction: { emoji: "🎉" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select 'turbo-stream[action="replace"][target="message_' + @message.id.to_s + '"]'
    assert_includes response.body, "Remove 🎉 reaction"
  end
end
