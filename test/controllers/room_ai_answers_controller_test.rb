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

  test "selected source and older target remain valid through explicit paid-result review and Send" do
    sign_in @alice
    older = @room.messages.create!(user: @bob,
      body: "What are the Rails registration acceptance criteria?")
    @room.messages.create!(user: @bob,
      body: "Please send the updated landing page.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Use verified facts only.")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    args = @payload.fetch(:answer)
    full_req = AiWorkspace::GenerationOrchestrator::Request.new(
      mode: "answer", actor: @alice, room: @room, draft_text: "",
      confirmed: "1", goal_source: "room_instructions",
      expected_goal_revision: 1, request_id: args.fetch(:request_id))
    full = AiWorkspace::GenerationOrchestrator.new.prepare(request: full_req).prepared
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: full, hint: "")
    selected_req = full_req.dup
    selected_req.source_token = token
    selected_req.selected_ids = [older.id]
    selected_req.reply_target_id = older.id
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: selected_req)
    contract = AiWorkspace::GenerationInputContract.build!(
      plan: plan, request: selected_req)
    assert_equal "M#{older.id}", JSON.parse(contract.user_content).fetch("reply_to_ref")
    text = "Please confirm the Rails registration acceptance criteria."
    result = AiWorkspace::AnswerGeneration::Result.new(
      text: text, model: "grok-4.3", cost_ticks: 10_000_000,
      source_ids: [older.id], goal_revision: 1,
      request_id: args.fetch(:request_id), fingerprint: contract.fingerprint)
    fake = Object.new
    fake.define_singleton_method(:call) { |**_opts| result }
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:new, -> { fake }) do
        post @url, params: { answer: args.merge(source_token: token,
          selected_ids: [older.id], reply_target_id: older.id) }, as: :json
      end
    end
    assert_response :success
    data = response.parsed_body
    assert_equal [older.id], data.fetch("source_ids")
    assert AiWorkspace::DraftProvenance.valid?(
      token: data.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: text)
    assert_difference "Message.count", 1 do
      post room_messages_path(@room), params: {
        message: { body: "", send_variant: "ai",
          ai_body: text, ai_source: text, ai_proof: data.fetch("provenance_token") }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
    assert_equal true, @room.messages.order(:id).last.ai_assisted?
    assert_equal "ai_generated", @room.messages.order(:id).last.origin
    assert_equal 0, AiUsageReservation.count
  end

  test "explicit synthetic request never calls xAI, never reserves budget and never Sends" do
    sign_in @alice
    @room.messages.create!(user: @bob, body: "POST /orders returns 422.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for reproducible validation evidence.")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        post @url, params: @payload, as: :json
      end
    end

    assert_response :success
    data = response.parsed_body
    assert_equal true, data.fetch("synthetic")
    assert_equal false, data.fetch("provider_called")
    assert_equal false, data.fetch("budget_reserved")
    assert_equal false, data.fetch("message_sent")
    assert_equal false, data.fetch("automatic_send_active")
    assert_equal "synthetic-local-no-ai", data.fetch("model")
    assert_equal "0.000000", data.fetch("cost_usd")
    assert_includes data.fetch("text"), "СИНТЕТИЧЕСКИЙ ТЕСТ"
    assert_equal 1, @room.messages.count
    assert_equal 0, AiUsageReservation.count
    assert AiWorkspace::DraftProvenance.valid?(
      token: data.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: data.fetch("text"))
  end

  test "unchanged synthetic candidate remains valid for an explicit server Send" do
    sign_in @alice
    @room.messages.create!(user: @bob, body: "POST /orders returns 422.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for reproducible validation evidence.")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        post @url, params: @payload, as: :json
      end
    end
    assert_response :success
    candidate = response.parsed_body
    assert_difference "Message.count", 1 do
      post room_messages_path(@room), params: {
        message: { body: "", send_variant: "ai",
          ai_body: candidate.fetch("text").gsub("\n", "\r\n"),
          ai_source: candidate.fetch("text").gsub("\n", "\r\n"),
          ai_proof: candidate.fetch("provenance_token") }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
    assert @room.messages.order(:id).last.ai_assisted?
    assert_equal "synthetic", @room.messages.order(:id).last.origin
    assert_equal candidate.fetch("text"), @room.messages.order(:id).last.body
    assert_equal 0, AiUsageReservation.count
  end

  test "peer-only history permits synthetic Answer and explicit Send without own history grant" do
    sign_in @alice
    own = @room.messages.create!(user: @alice, body: "Withheld private author note")
    peer = @room.messages.create!(user: @bob, body: "POST orders returns a validation error.")
    RoomAiInstructionRevision.create!(room: @room, editor: @alice,
      revision_number: 1, content: "Ask for reproducible validation evidence.")
    grant = AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob)
    grant.grant!
    AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
      AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
        post @url, params: @payload, as: :json
      end
    end
    assert_response :success
    candidate = response.parsed_body
    assert_equal [peer.id], candidate.fetch("source_ids")
    assert_not_includes response.body, own.body
    assert AiWorkspace::DraftProvenance.valid?(
      token: candidate.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: candidate.fetch("text"))
    assert_difference "Message.count", 1 do
      post room_messages_path(@room), params: {
        message: { body: "", send_variant: "ai", ai_body: candidate.fetch("text"),
          ai_source: candidate.fetch("text"), ai_proof: candidate.fetch("provenance_token") }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
    assert_equal 0, AiUsageReservation.count
    grant.revoke!
    assert_not AiWorkspace::DraftProvenance.valid?(
      token: candidate.fetch("provenance_token"), actor: @alice, room: @room,
      source_text: candidate.fetch("text"))
  end

  %w[revoked edited deleted].each do |change|
    test "explicit Send rejects contextual candidate after source is #{change}" do
      sign_in @alice
      source = @room.messages.create!(user: @bob, body: "Original validation evidence.")
      RoomAiInstructionRevision.create!(room: @room, editor: @alice,
        revision_number: 1, content: "Use authorized evidence only.")
      grant = AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob)
      grant.grant!
      AiWorkspace::AnswerGeneration.stub(:enabled?, true) do
        AiWorkspace::AnswerGeneration.stub(:synthetic_enabled?, true) do
          post @url, params: @payload, as: :json
        end
      end
      assert_response :success
      candidate = response.parsed_body
      assert_equal [source.id], candidate.fetch("source_ids")
      case change
      when "revoked" then grant.revoke!
      when "edited" then source.update!(body: "Changed validation evidence.")
      when "deleted" then source.destroy!
      end

      assert_no_difference ["Message.count", "AiUsageReservation.count"] do
        post room_messages_path(@room), params: { message: {
          body: "Never silently send this fallback", send_variant: "ai",
          ai_body: candidate.fetch("text"), ai_source: candidate.fetch("text"),
          ai_proof: candidate.fetch("provenance_token")
        } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :unprocessable_entity
      assert_match(/no message sent/i, response.body)
    end
  end

end
