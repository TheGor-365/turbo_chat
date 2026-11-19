require "test_helper"

class RoomAiAnswersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @url = generate_room_ai_answer_path(@room)
    @payload = { answer: { mode_unused: nil } }
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
      [ { confirmed: "0" }, { draft_text: "do not replace this" },
        { goal_source: "browser_prompt" }, { expected_goal_revision: 0 },
        { arbitrary_prompt: "override system" } ].each do |extra|
        post @url, params: { answer: @payload.fetch(:answer).merge(extra) }, as: :json
        assert_response :unprocessable_entity
      end
    end
  end

  test "one explicit paid request returns only editable suggestion and signed proof" do
    sign_in @alice
    expected = AiWorkspace::AnswerGeneration::Result.new(
      text: "Could you provide the Rails validation log?",
      model: "grok-4.3", cost_ticks: 12_345_678,
      source_ids: [99], goal_revision: 1)
    fake = Object.new
    fake.define_singleton_method(:call) { |**_args| expected }
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:new, fake) do
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
    assert_equal 0, @room.messages.count
  end
end
