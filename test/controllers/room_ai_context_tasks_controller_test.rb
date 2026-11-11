require "test_helper"

class RoomAiContextTasksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @room.messages.create!(user: @bob, body: "Please propose the next steps.")
  end

  test "context tasks are disabled independently in test and cannot publish" do
    sign_in @alice
    count = Message.count
    post generate_room_ai_context_task_path(@room), params: {
      task: { kind: "client_brief", request_id: SecureRandom.uuid, consent: "1" }
    }
    assert_response :service_unavailable
    assert_equal count, Message.count
    assert_equal "no-store", response.headers["Cache-Control"].split(", ").last
  end

  test "unapproved participant history and forged tasks are denied" do
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: @alice).grant!
    sign_in @alice
    AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
      post generate_room_ai_context_task_path(@room), params: {
        task: { kind: "client_proposal", request_id: SecureRandom.uuid, consent: "1" }
      }
      assert_response :unprocessable_entity
      assert_not_includes response.body, "Please propose"

      post generate_room_ai_context_task_path(@room), params: {
        task: { kind: "arbitrary_prompt", request_id: SecureRandom.uuid, consent: "1" }
      }
      assert_response :unprocessable_entity
    end
  end
  test "returns only room-owned source links and never creates a message" do
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    incoming = @room.messages.first
    output = AiWorkspace::ContextTaskGeneration::Result.new(
      text: "Review [M#{incoming.id}]", kind: "client_brief", model: "fake",
      source_ids: [incoming.id], omitted: 0, cost_ticks: 0
    )
    fake = Object.new
    fake.define_singleton_method(:call) { |**_| output }
    sign_in @alice
    before = Message.count
    AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:new, fake) do
        post generate_room_ai_context_task_path(@room), params: {
          task: { kind: "client_brief", request_id: SecureRandom.uuid, consent: "1" }
        }
      end
    end
    error = request.env["action_dispatch.exception"]
    assert_response :success, "Exception: #{error&.class}: #{error&.message}; #{error&.backtrace&.first(5)&.join(' | ')}"
    body = JSON.parse(response.body)
    assert_equal({ incoming.id.to_s => room_path(@room, focus: incoming.id) }, body.fetch("source_links"))
    assert_equal [incoming.id], body.fetch("source_message_ids")
    assert_equal before, Message.count
  end

  test "foreign or deleted citation IDs fail closed even if a generator returns them" do
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    outsider_room = Room.create!(name: "Outside", kind: "private_group", is_private: true, owner: @bob)
    outsider_room.participants.create!(user: @bob, group_role: "owner")
    foreign = outsider_room.messages.create!(user: @bob, body: "Do not expose this source")
    result = AiWorkspace::ContextTaskGeneration::Result.new(
      text: "False citation", kind: "client_brief", model: "fake",
      source_ids: [foreign.id], omitted: 0, cost_ticks: 0
    )
    fake = Object.new
    fake.define_singleton_method(:call) { |**_| result }
    sign_in @alice
    AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:new, fake) do
        post generate_room_ai_context_task_path(@room), params: {
          task: { kind: "client_brief", request_id: SecureRandom.uuid, consent: "1" }
        }
      end
    end
    assert_response :unprocessable_entity
    assert_not_includes response.body, "Do not expose this source"
  end

end
