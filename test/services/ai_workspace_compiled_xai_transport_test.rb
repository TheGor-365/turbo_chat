require "test_helper"
require "json"
require "securerandom"

# Contract-to-wire audit: a fake HTTP response, never a paid network request.
class AiWorkspaceCompiledXaiTransportTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "POST /orders returns 422; we have not agreed a delivery date or price.")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for validation evidence; do not invent prices.")
    request = AiWorkspace::GenerationOrchestrator::Request.new(
      mode: "answer", actor: @alice, room: @room, draft_text: "",
      request_id: SecureRandom.uuid, confirmed: "1",
      goal_source: "room_instructions", expected_goal_revision: 1)
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: request)
    @compiled = AiWorkspace::GenerationInputContract.build!(
      plan: plan, request: request)
  end

  def response_payload
    { status: "completed", model: "grok-4.3",
      output: [{ type: "message", role: "assistant",
        content: [{ type: "output_text",
          text: "Please share the Rails validation error and example request." }] }],
      usage: { input_tokens: 99, output_tokens: 34,
        cost_in_usd_ticks: 250_000 } }.to_json
  end

  test "compiled, versioned goal and only approved source go to provider with no tools or storage" do
    captured = nil
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-no-network-key",
      transport: ->(request) {
        captured = request
        FakeResponse.new("200", response_payload)
      })
    before = Message.count
    output = adapter.generate_compiled!(@compiled)
    assert_equal before, Message.count
    assert_equal "Please share the Rails validation error and example request.", output.text
    assert_equal 250_000, output.cost_in_usd_ticks
    assert_equal "/v1/responses", captured.path
    assert_equal "Bearer xai-test-no-network-key", captured["Authorization"]
    body = JSON.parse(captured.body)
    assert_equal "grok-4.3", body.fetch("model")
    assert_equal false, body.fetch("store")
    assert_equal [], body.fetch("tools")
    assert_equal 384, body.fetch("max_output_tokens")
    assert_equal({ "effort" => "none" }, body.fetch("reasoning"))
    assert_equal "system", body.fetch("input")[0].fetch("role")
    assert_equal @compiled.system_instruction, body.fetch("input")[0].fetch("content")
    assert_equal "user", body.fetch("input")[1].fetch("role")
    assert_equal @compiled.user_content, body.fetch("input")[1].fetch("content")
    user_data = JSON.parse(body.fetch("input")[1].fetch("content"))
    assert_equal "suggest_reply_for_human_review", user_data.fetch("task")
    assert_equal 1, user_data.dig("personal_goal", "revision")
    assert_equal "room_instructions", user_data.dig("personal_goal", "scope")
    assert_equal "Ask for validation evidence; do not invent prices.",
      user_data.dig("personal_goal", "text")
    assert_equal ["M#{@incoming.id}"], user_data.fetch("excerpts").map { |row| row.fetch("ref") }
    assert_includes user_data.fetch("excerpts").sole.fetch("text"), "POST /orders returns 422"
    refute_includes captured.body, "xai-test-no-network-key"
  end

  test "other generation modes and missing billing usage never produce an accepted answer" do
    calls = 0
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-no-network-key",
      transport: ->(_request) {
        calls += 1
        bad = JSON.parse(response_payload)
        bad.delete("usage")
        FakeResponse.new("200", bad.to_json)
      })
    other_mode = @compiled.dup
    other_mode.mode = "auto_reply"
    assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
      adapter.generate_compiled!(other_mode)
    end
    assert_equal 0, calls
    assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
      adapter.generate_compiled!(@compiled)
    end
    assert_equal 1, calls
    assert_equal 1, @room.messages.count
  end
end
