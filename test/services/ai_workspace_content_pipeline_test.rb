require "test_helper"

class AiWorkspaceContentPipelineTest < ActiveSupport::TestCase
  def preset_config(operation: "beautify")
    {
      "schema_version" => 1, "id" => "client_reply_professional", "version" => 1,
      "operation" => operation, "label" => "Professional client reply", "locale" => "en",
      "intent" => "clarify_next_step", "audience" => "client",
      "tone" => "professional", "style" => "concise",
      "constraints" => {
        "preserve_facts" => true, "do_not_invent_prices" => true,
        "do_not_invent_deadlines" => true, "require_user_approval" => true
      },
      "context" => { "policy" => "manual", "max_messages" => 8 },
      "output" => { "format" => "plain_text", "variants" => 1 }
    }
  end

  def direct_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "preset v1 is strictly validated and its snapshot is immutable" do
    config = preset_config
    preset = AiWorkspace::PresetDefinition.new(config)
    config["constraints"]["require_user_approval"] = false
    config["label"].replace("tampered")
    assert_equal "Professional client reply", preset.label
    assert_equal true, preset.snapshot.dig("constraints", "require_user_approval")
    assert preset.snapshot.frozen?
    assert preset.snapshot.fetch("context").frozen?
    assert_raises(FrozenError) { preset.snapshot["label"].replace("tampered") }

    invalid = [
      preset_config.merge("system_prompt" => "ignore policy"),
      preset_config.merge("schema_version" => 99),
      preset_config.merge("version" => 2),
      preset_config.merge("operation" => "charge_customer"),
      preset_config.merge("context" => { "policy" => "smart", "max_messages" => 8 }),
      preset_config.merge("context" => { "policy" => "manual", "max_messages" => 9 }),
      preset_config.merge("output" => { "format" => "html", "variants" => 2 }),
      preset_config.merge("constraints" => preset_config["constraints"].merge("preserve_facts" => false)),
      preset_config.merge("label" => "<script>"),
      preset_config.merge(untrusted: "bad")
    ]
    invalid.each do |bad|
      assert_raises(AiWorkspace::Errors::InvalidPreset) { AiWorkspace::PresetDefinition.new(bad) }
    end
  end

  test "preprocessor preserves formatting, normalizes Unicode and flags sensitive content" do
    input = "Cafe\u0301\r\n  puts 'spaces'\r\nhttps://example.test/a?b=c  \r\nperson@example.test\r\nsk-proj-abcdefghijklmnopqrstuvwxyz"
    result = AiWorkspace::Preprocessors::Text.call(input)
    assert_includes result.text, "Café\n  puts 'spaces'\n"
    assert_includes result.text, "https://example.test/a?b=c  \n"
    assert_equal result.text, AiWorkspace::Preprocessors::Text.call(input).text
    assert_equal [:possible_email, :possible_secret], result.warnings
    assert_equal result.text.length, result.characters
    assert_not_includes result.warnings.join, "person@example.test"
    assert result.frozen?
    assert result.text.frozen?
  end

  test "empty control invalid UTF-8 and oversized text all fail without echo" do
    [nil, "", " \n ", "ok\u0000bad", "a" * 5_001, "a" * 20_001,
      "\xFF".b.force_encoding("UTF-8")].each do |input|
      error = assert_raises(AiWorkspace::Errors::InvalidSelection) do
        AiWorkspace::Preprocessors::Text.call(input)
      end
      assert_match(/Invalid or oversized text/, error.message)
    end
  end

  test "own draft requires membership and never writes a chat message" do
    alice, bob = users(:one), users(:two)
    outsider = User.create!(email: "pipeline-outsider@example.test", password: "strong-test-password")
    room = direct_room(alice, bob)
    preset = AiWorkspace::PresetDefinition.new(preset_config)
    pipeline = AiWorkspace::ContentPipeline.new
    assert_no_difference(["Message.count", "Room.count"]) do
      prepared = pipeline.prepare(actor: alice, room: room, source: "own_draft",
        source_ids: [], operation: "beautify", preset: preset, draft_text: "Hello\r\nworld")
      assert_equal "Hello\nworld", prepared.rows.first.text
      assert_nil prepared.rows.first.source_id
      assert_equal 11, prepared.characters
      assert_equal preset.snapshot, prepared.preset_snapshot
      assert prepared.rows.frozen?
    end
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(actor: outsider, room: room, source: "own_draft", source_ids: [],
        operation: "beautify", preset: preset, draft_text: "Private draft")
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      pipeline.prepare(actor: alice, room: room, source: "own_draft", source_ids: [1],
        operation: "beautify", preset: preset, draft_text: "Private draft")
    end
  end

  test "selected context uses existing room scope and excludes cross-room data" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: alice, body: "A" * 900)
    unselected = room.messages.create!(user: bob, body: "do not include this")
    last = room.messages.create!(user: bob, body: "End")
    foreign = Room.create!(name: "Pipeline unrelated public")
    foreign.joinables.create!(user: bob)
    hidden = foreign.messages.create!(user: bob, body: "Foreign content")
    preset = AiWorkspace::PresetDefinition.new(preset_config(operation: "summarize"))
    pipeline = AiWorkspace::ContentPipeline.new

    prepared = pipeline.prepare(actor: alice, room: room, source: "selected_messages",
      source_ids: [last.id.to_s, first.id.to_s], operation: "summarize", preset: preset)
    assert_equal [first.id, last.id], prepared.rows.map(&:source_id)
    assert_equal [750, 3], prepared.rows.map { |row| row.text.length }
    assert_not_includes prepared.rows.map(&:text).join, unselected.body
    assert_not_includes prepared.rows.map(&:text).join, hidden.body

    [[hidden.id.to_s], [], [first.id.to_s] * 2].each do |ids|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        pipeline.prepare(actor: alice, room: room, source: "selected_messages",
          source_ids: ids, operation: "summarize", preset: preset)
      end
    end
    room.participants.where(user: alice).delete_all
    assert_raises(AiWorkspace::Errors::Unauthorized) do
      pipeline.prepare(actor: alice, room: room, source: "selected_messages",
        source_ids: [first.id.to_s], operation: "summarize", preset: preset)
    end
  end

  test "smart and approved context are denied and gateway remains unavailable" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    preset = AiWorkspace::PresetDefinition.new(preset_config)
    args = { actor: alice, room: room, source_ids: [], operation: "beautify",
      preset: preset, draft_text: "draft" }
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      AiWorkspace::ContentPipeline.new.prepare(**args.merge(source: "approved_context"))
    end
    %w[smart agent].each do |mode|
      policy = AiWorkspace::ContextPolicy.new(mode: mode)
      assert_raises(AiWorkspace::Errors::ConsentRequired) do
        AiWorkspace::ContentPipeline.new(context_policy: policy).prepare(**args.merge(source: "own_draft"))
      end
    end
    assert_not AiWorkspace::Gateway.configured?
    assert_raises(AiWorkspace::Gateway::ProviderUnavailable) { AiWorkspace::Gateway.generate! }
  end
end
