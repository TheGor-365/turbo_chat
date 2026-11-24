require "test_helper"
require "minitest/mock"
require "tmpdir"

class AiManualDraftGenerationTest < ActiveSupport::TestCase
  class FakeXai
    attr_reader :seen
    def generate!(prepared)
      @seen = prepared
      AiWorkspace::Providers::XaiResponses::Result.new(
        text: "A polished test sentence.", model: "grok-4.3",
        input_tokens: 35, output_tokens: 10, cost_in_usd_ticks: 500_000)
    end
  end

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
  end

  test "manual one-draft call rechecks membership and persists metered cost without writing messages" do
    Dir.mktmpdir("h3c_service") do |dir|
      fake = FakeXai.new
      ledger = AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json"))
      service = AiWorkspace::ManualDraftGeneration.new(
        ledger: ledger, provider_factory: ->(_key) { fake })
      original_count = Message.count

      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-test-only-no-real-key") do
          result = service.call(actor: @alice, room: @room,
            draft_text: "A safe dummy text.", preset_id: "polish_clarity",
            request_id: SecureRandom.uuid, confirmed: "1")
          assert_equal "A polished test sentence.", result.text
          assert_equal "own_draft", fake.seen.source
          assert_equal 500_000, result.cost_ticks
        end
      end
      assert_equal original_count, Message.count
      values = JSON.parse(File.read(File.join(dir, "ledger.json"))).fetch("entries").values
      assert_equal [500_000], values.map { |v| v.fetch("charged_ticks") }
    end
  end

  test "missing consent denies before a budget reservation or provider call" do
    Dir.mktmpdir("h3c_consent") do |dir|
      ledger = AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json"))
      service = AiWorkspace::ManualDraftGeneration.new(ledger: ledger)
      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        [nil, "true", "0", true].each do |bad|
          assert_raises(AiWorkspace::Errors::ConsentRequired) do
            service.call(actor: @alice, room: @room,
              draft_text: "Safe dummy.", preset_id: "polish_clarity",
              request_id: SecureRandom.uuid, confirmed: bad)
          end
        end
      end
      assert_not File.exist?(File.join(dir, "ledger.json"))
    end
  end

  test "translation carries explicit target to trusted provider and never writes messages" do
    Dir.mktmpdir("h3f3_service") do |dir|
      fake = FakeXai.new
      ledger = AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json"))
      service = AiWorkspace::ManualDraftGeneration.new(
        ledger: ledger, provider_factory: ->(_key) { fake })
      count = Message.count
      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-test-only-no-real-key") do
          service.call(actor: @alice, room: @room,
            draft_text: "Safe synthetic translation.", preset_id: "translate_preserving_tone",
            target_locale: "ru", request_id: SecureRandom.uuid, confirmed: "1")
        end
      end
      assert_equal "translate", fake.seen.operation
      assert_equal "ru", fake.seen.target_locale
      assert_equal count, Message.count
      assert File.exist?(File.join(dir, "ledger.json"))
    end
  end

  test "invalid target language is denied before budget reservation" do
    Dir.mktmpdir("h3f3_invalid") do |dir|
      ledger_path = File.join(dir, "ledger.json")
      service = AiWorkspace::ManualDraftGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: ledger_path))
      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        assert_raises(AiWorkspace::Errors::InvalidSelection) do
          service.call(actor: @alice, room: @room, draft_text: "Safe dummy.",
            preset_id: "translate_preserving_tone", request_id: SecureRandom.uuid,
            confirmed: "1", target_locale: "fr")
        end
      end
      assert_not File.exist?(ledger_path)
    end
  end

  test "conflicting translation parameters refuse before budget reservation or provider call" do
    Dir.mktmpdir("h3c_translation_options") do |dir|
      ledger_path = File.join(dir, "ledger.json")
      service = AiWorkspace::ManualDraftGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: ledger_path),
        provider_factory: ->(_key) { raise "Provider must not be called" })
      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        assert_raises(AiWorkspace::Errors::InvalidSelection) do
          service.call(actor: @alice, room: @room,
            draft_text: "Please translate.", preset_id: "translate_preserving_tone",
            target_locale: "ru", writing_tone: "warm",
            request_id: SecureRandom.uuid, confirmed: "1")
        end
      end
      assert_not File.exist?(ledger_path)
    end
  end

  test "personal OFF blocks only that actor before budget and dispatch" do
    AiWorkspace::PersonalEnablement.write(actor: @alice, enabled: false, expected_revision: 0)
    Dir.mktmpdir("personal_ai") do |dir|
      path = File.join(dir, "ledger.json")
      fake = FakeXai.new
      service = AiWorkspace::ManualDraftGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path),
        provider_factory: ->(_key) { fake })
      AiWorkspace::ManualDraftGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-test-only-no-real-key") do
          args = {room: @room, draft_text: "Safe dummy.", preset_id: "polish_clarity", confirmed: "1"}
          assert_raises(AiWorkspace::Errors::ConsentRequired) do
            service.call(**args, actor: @alice, request_id: SecureRandom.uuid)
          end
          assert_not File.exist?(path)
          assert_nil fake.seen
          assert_equal "A polished test sentence.", service.call(**args,
            actor: @bob, request_id: SecureRandom.uuid).text
        end
      end
    end
  end

  test "provider stays blocked in test and production even with a secret present" do
    assert_not AiWorkspace::ManualDraftGeneration.enabled?
  end
end
