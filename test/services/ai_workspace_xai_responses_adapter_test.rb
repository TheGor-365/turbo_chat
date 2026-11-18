require "test_helper"

class XaiResponsesAdapterTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)
  def setup
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    @prepared = AiWorkspace::OwnDraftPreflight.new.prepare(
      actor: alice, room: room, preset_id: "polish_clarity",
      approved_preview: true, draft_text: "Please check my draft.")
  end

  def provider_response(text: "Please review my draft.", status: "completed")
    {
      status: status, model: "grok-4.3",
      output: [{ type: "message", role: "assistant",
        content: [{ type: "output_text", text: text }] }],
      usage: { input_tokens: 60, output_tokens: 35, cost_in_usd_ticks: 162500 }
    }.to_json
  end

  test "fixed xAI Responses shape sends only own draft without storage or tools" do
    transmitted = nil
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-key-never-real",
      transport: ->(request) {
        transmitted = request
        FakeResponse.new("200", provider_response)
      })
    output = adapter.generate!(@prepared)

    assert_equal "/v1/responses", transmitted.path
    assert_equal "Bearer xai-test-key-never-real", transmitted["Authorization"]
    payload = JSON.parse(transmitted.body)
    assert_equal "grok-4.3", payload["model"]
    assert_equal false, payload["store"]
    assert_equal [], payload["tools"]
    assert_equal 800, payload["max_output_tokens"]
    assert_equal "system", payload["input"][0]["role"]
    assert_equal "user", payload["input"][1]["role"]
    assert_equal "Please check my draft.", payload["input"][1]["content"]
    assert_includes payload["input"][0]["content"], "Correct spelling, grammar"
    assert_includes payload["input"][0]["content"], "do not return an unchanged copy"
    assert_includes payload["input"][0]["content"], "If the draft is already correct"
    assert_not_includes transmitted.body, "xai-test-key-never-real"
    assert_equal "Please review my draft.", output.text
    assert_equal 162500, output.cost_in_usd_ticks
    assert_not AiWorkspace::Gateway.configured?
  end

  test "all six presets produce distinct trusted prompts without room context" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    expected_words = {
      "polish_clarity" => "Correct spelling, grammar",
      "professional_client_reply" => "professional reply to a client",
      "friendly" => "friendly, natural",
      "concise" => "Shorten the author's unsent draft",
      "translate_preserving_tone" => "Target language: Armenian",
      "technical_summary" => "technical information explicitly present"
    }

    expected_words.each do |preset_id, phrase|
      target_locale = preset_id == "translate_preserving_tone" ? "hy" : nil
      prepared = AiWorkspace::OwnDraftPreflight.new.prepare(
        actor: alice, room: room, draft_text: "Only my synthetic draft.",
        preset_id: preset_id, target_locale: target_locale, approved_preview: true)
      sent = nil
      adapter = AiWorkspace::Providers::XaiResponses.new(
        api_key: "xai-test-key-never-real",
        transport: ->(request) {
          sent = JSON.parse(request.body)
          FakeResponse.new("200", provider_response(text: "Safe suggestion"))
        })
      output = adapter.generate!(prepared)
      assert_equal "Safe suggestion", output.text
      assert_includes sent.fetch("input").first.fetch("content"), phrase
      assert_equal "Only my synthetic draft.", sent.fetch("input").last.fetch("content")
      assert_equal false, sent.fetch("store")
      assert_equal [], sent.fetch("tools")
      assert_equal 2, sent.fetch("input").size
    end
  end

  test "forged operations and locale cannot reach external transport" do
    calls = 0
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-key-never-real",
      transport: ->(_request) {
        calls += 1
        FakeResponse.new("200", provider_response)
      })
    wrong_operation = @prepared.dup
    wrong_operation.operation = "summarize"
    rogue_locale = @prepared.dup
    rogue_locale.target_locale = "ru"
    [wrong_operation, rogue_locale].each do |forged|
      assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
        adapter.generate!(forged)
      end
    end
    assert_equal 0, calls
  end

  test "invalid or missing key cannot reach transport" do
    [nil, "", "sk-pretend", "xai-short"].each do |key|
      assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
        AiWorkspace::Providers::XaiResponses.new(api_key: key)
      end
    end
  end

  test "rejects selected context and private identifiers before dispatch" do
    calls = 0
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-key-never-real",
      transport: ->(_request) { calls += 1; FakeResponse.new("200", provider_response) })
    forged = @prepared.dup
    forged.source = "selected_messages"
    assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
      adapter.generate!(forged)
    end
    flagged = @prepared.dup
    flagged.rows = [AiWorkspace::ContentPipeline::Row.new(
      source_id: nil, text: "My email is private@example.test", warnings: [])]
    assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
      adapter.generate!(flagged)
    end
    assert_equal 0, calls
  end

  test "fails closed for missing billing usage and non-complete responses" do
    bad = JSON.parse(provider_response)
    bad.delete("usage")
    incomplete = provider_response(status: "incomplete")
    large = provider_response(text: "a" * 5001)
    [bad.to_json, incomplete, large, "{broken"].each do |payload|
      adapter = AiWorkspace::Providers::XaiResponses.new(
        api_key: "xai-test-key-never-real",
        transport: ->(_request) { FakeResponse.new("200", payload) })
      assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
        adapter.generate!(@prepared)
      end
    end
  end

  test "fails closed for HTTP refusal and refuses silent auto retry" do
    calls = 0
    adapter = AiWorkspace::Providers::XaiResponses.new(
      api_key: "xai-test-key-never-real",
      transport: ->(_request) {
        calls += 1
        FakeResponse.new("429", '{"error":{"message":"Do not leak me"}}')
      })
    error = assert_raises(AiWorkspace::Providers::XaiResponses::ProviderUnavailable) do
      adapter.generate!(@prepared)
    end
    assert_equal "Provider unavailable.", error.message
    assert_equal 1, calls
  end
end
