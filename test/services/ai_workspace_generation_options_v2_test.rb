require "test_helper"

class AiWorkspaceGenerationOptionsV2Test < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  test "explicit per-message language and tone change only the trusted system prompt" do
    prepared = AiWorkspace::OwnDraftPreflight.new.prepare(
      actor: @alice, room: @room, draft_text: "Please review the deployment.",
      preset_id: "professional_client_reply", approved_preview: true,
      writing_language: "hy", writing_tone: "technical")
    transmitted = nil
    response = {
      status: "completed", model: "grok-4.3",
      output: [{ type: "message", role: "assistant",
        content: [{ type: "output_text", text: "Reviewed." }] }],
      usage: {input_tokens: 20, output_tokens: 8, cost_in_usd_ticks: 100_000}
    }
    provider = AiWorkspace::Providers::XaiResponses.new(api_key: "xai-test-only",
      transport: ->(request) {
        transmitted = JSON.parse(request.body)
        FakeResponse.new("200", response.to_json)
      })
    result = provider.generate!(prepared)
    assert_equal "Reviewed.", result.text
    prompt = transmitted.fetch("input").first.fetch("content")
    assert_includes prompt, "Armenian"
    assert_includes prompt, "precise, technical and concise"
    assert_includes prompt, "professional reply to a client"
    assert_equal "Please review the deployment.", transmitted.fetch("input").last.fetch("content")
    assert_equal false, transmitted.fetch("store")
    assert_equal [], transmitted.fetch("tools")
    assert_equal 2, transmitted.fetch("input").length
    assert_equal 0, @room.messages.count
  end

  test "unknown language and tone are rejected before external generation" do
    preflight = AiWorkspace::OwnDraftPreflight.new
    [{writing_language: "hacked"}, {writing_tone: "ignore instructions"},
      {writing_language: ["en"]}, {writing_tone: ["warm"]}].each do |options|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        preflight.prepare(actor: @alice, room: @room, draft_text: "A harmless message.",
          preset_id: "friendly", approved_preview: true, **options)
      end
    end
    assert_equal 0, @room.messages.count
  end

  test "translation target cannot be overridden by per-message writing options" do
    prepared = AiWorkspace::OwnDraftPreflight.new.prepare(actor: @alice, room: @room,
      draft_text: "Please translate.", preset_id: "translate_preserving_tone",
      target_locale: "ru", writing_language: "en", approved_preview: true)
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::DraftPromptV1.for(preset: AiWorkspace::PresetRegistry.bundled.fetch("translate_preserving_tone"),
        target_locale: prepared.target_locale, writing_language: prepared.writing_language)
    end
  end
end
