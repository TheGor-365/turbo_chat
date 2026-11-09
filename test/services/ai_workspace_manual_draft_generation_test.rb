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

  test "provider stays blocked in test and production even with a secret present" do
    assert_not AiWorkspace::ManualDraftGeneration.enabled?
  end
end
