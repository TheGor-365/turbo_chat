require "test_helper"

class AiWorkspaceContextTaskTransportTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  test "all five business tasks send only bounded evidence with no tools or storage" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    [alice, bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
    message = room.messages.create!(user: bob, body: "Let's discuss the scope.")
    bundle = AiWorkspace::ReplyContextBuilder.new.build(room: room, actor: alice)
    AiWorkspace::ConversationTaskV1::TASKS.each_key do |kind|
      sent = nil
      adapter = AiWorkspace::Providers::XaiResponses.new(
        api_key: "xai-test-key-never-real",
        transport: ->(request) {
          sent = JSON.parse(request.body)
          FakeResponse.new("200", {
            status: "completed", model: "grok-4.3",
            output: [{ type: "message", role: "assistant",
              content: [{ type: "output_text", text: "To confirm." }] }],
            usage: { input_tokens: 100, output_tokens: 20,
              cost_in_usd_ticks: 130_000 }
          }.to_json)
        }
      )
      output = adapter.generate_context_task!(bundle, kind: kind, hint: "")
      assert_equal "To confirm.", output.text
      assert_equal false, sent.fetch("store")
      assert_equal [], sent.fetch("tools")
      assert_equal 2, sent.fetch("input").size
      assert_includes sent.fetch("input").first.fetch("content"), "untrusted data"
      assert_equal AiWorkspace::ConversationTaskV1::TASKS.fetch(kind).fetch(:max_output_tokens),
        sent.fetch("max_output_tokens")
      payload = JSON.parse(sent.fetch("input").last.fetch("content"))
      assert_equal kind, payload.fetch("task")
      assert_equal "M#{message.id}", payload.fetch("excerpts").first.fetch("ref")
    end
  end
end
