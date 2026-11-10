require "test_helper"
require "minitest/mock"
require "tmpdir"

class AiWorkspaceContextTaskGenerationTest < ActiveSupport::TestCase
  class FakeProvider
    attr_reader :kind, :bundle, :hint, :calls
    def initialize
      @calls = 0
    end
    def generate_context_task!(bundle, kind:, hint:)
      @calls += 1
      @kind, @bundle, @hint = kind, bundle, hint
      AiWorkspace::Providers::XaiResponses::Result.new(
        text: "Next step: review the agreed scope [M#{bundle.source_ids.first}]",
        model: "grok-4.3", input_tokens: 155, output_tokens: 55,
        cost_in_usd_ticks: 500_000
      )
    end
  end

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @message = @room.messages.create!(user: @bob, body: "Please review the agreed scope.")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "client brief uses evidence, charges ledger and never stores or sends" do
    Dir.mktmpdir("h3g_task") do |dir|
      provider = FakeProvider.new
      ledger = AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json"))
      service = AiWorkspace::ContextTaskGeneration.new(ledger: ledger,
        provider_factory: ->(_key) { provider })
      count = Message.count
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-testing-not-real") do
          result = service.call(actor: @alice, room: @room,
            kind: "client_brief", request_id: SecureRandom.uuid,
            confirmed: "1", hint: "Short outline please.")
          assert_equal "client_brief", result.kind
          assert_equal [@message.id], result.source_ids
          assert_includes result.text, "[M#{@message.id}]"
          assert_equal "client_brief", provider.kind
          assert_equal "Short outline please.", provider.hint
        end
      end
      assert_equal 1, provider.calls
      assert_equal count, Message.count
      assert File.exist?(File.join(dir, "ledger.json"))
    end
  end

  test "invalid task and missing consent do not spend or contact model" do
    Dir.mktmpdir("h3g_invalid_task") do |dir|
      ledger_path = File.join(dir, "ledger.json")
      service = AiWorkspace::ContextTaskGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: ledger_path)
      )
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        assert_raises(AiWorkspace::Errors::InvalidSelection) do
          service.call(actor: @alice, room: @room,
            kind: "arbitrary", request_id: SecureRandom.uuid, confirmed: "1")
        end
        assert_raises(AiWorkspace::Errors::ConsentRequired) do
          service.call(actor: @alice, room: @room,
            kind: "client_brief", request_id: SecureRandom.uuid, confirmed: "0")
        end
      end
      assert_not File.exist?(ledger_path)
    end
  end

  test "feature flag is off in test and production" do
    assert_not AiWorkspace::ContextTaskGeneration.enabled?
  end
end
