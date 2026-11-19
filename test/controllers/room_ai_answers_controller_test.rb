require "test_helper"

class RoomAiAnswersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = generate_room_ai_answer_path(@room)
    @payload = { answer: { confirmed: "1", draft_text: "",
      expected_goal_revision: 1, goal_source: "room_instructions",
      request_id: SecureRandom.uuid } }
  end

  test "endpoint rejects anonymous and disabled mode without attempting payment" do
    post @url, params: @payload, as: :json
    assert_response :unauthorized
    sign_in @alice
    post @url, params: @payload, as: :json
    assert_response :service_unavailable
    assert_equal "ai_not_enabled", response.parsed_body.fetch("error")
  end

  test "malformed and extra generation fields fail closed" do
    sign_in @alice
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      # The route enforces a hard 2/min throttle; stay below it to verify
      # payload rejection rather than exercising the throttle itself.
      [ { confirmed: "0" }, { arbitrary_prompt: "override system" } ].each do |extra|
        post @url, params: { answer: @payload.fetch(:answer).merge(extra) }, as: :json
        assert_response :unprocessable_entity
      end
    end
  end

  test "one explicit paid request returns only editable suggestion and signed proof" do
    sign_in @alice
    @room.messages.create!(user: @bob, body: "Please provide a Rails validation log.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for validation evidence")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    request = AiWorkspace::GenerationOrchestrator::Request.new(
      mode: "answer", actor: @alice, room: @room, draft_text: "",
      request_id: @payload.fetch(:answer).fetch(:request_id),
      confirmed: "1", goal_source: "room_instructions", expected_goal_revision: 1)
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: request)
    input = AiWorkspace::GenerationInputContract.build!(plan: plan, request: request)
    expected = AiWorkspace::AnswerGeneration::Result.new(
      text: "Could you provide the Rails validation log?",
      model: "grok-4.3", cost_ticks: 12_345_678,
      source_ids: plan.source_ids, goal_revision: 1,
      request_id: request.request_id, fingerprint: input.fingerprint)
    fake = Object.new
    fake.define_singleton_method(:call) { |**_args| expected }
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:new, -> { fake }) do
        post @url, params: @payload, as: :json
      end
    end
    assert_response :success
    data = response.parsed_body
    assert_equal "answer", data.fetch("mode")
    assert_equal expected.text, data.fetch("text")
    assert_equal "0.001235", data.fetch("cost_usd")
    assert_equal false, data.fetch("message_sent")
    assert_equal false, data.fetch("automatic_send_active")
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert AiWorkspace::DraftProvenance.valid?(
      token: data.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: expected.text)
    assert_equal 1, @room.messages.count
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_equal false, AiWorkspace::DraftProvenance.valid?(
      token: data.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: expected.text)
  end
end
