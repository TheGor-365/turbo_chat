require "test_helper"
require "minitest/mock"
require "tmpdir"

class AiWorkspaceContextReplyGenerationTest < ActiveSupport::TestCase
  class FakeProvider
    attr_reader :bundle, :hint, :calls

    def initialize
      @calls = 0
    end

    def generate_reply!(bundle, hint:)
      @calls += 1
      @bundle, @hint = bundle, hint
      AiWorkspace::Providers::XaiResponses::Result.new(
        text: "Could you clarify the agreed deadline?", model: "grok-4.3",
        input_tokens: 190, output_tokens: 28, cost_in_usd_ticks: 500_000
      )
    end
  end

  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @question = @room.messages.create!(user: @bob,
      body: "Can we agree on a project deadline?")
  end

  def grant(user)
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
  end

  test "one click explicit consent charges once and returns cited source IDs but posts no message" do
    grant(@alice)
    grant(@bob)
    Dir.mktmpdir("h3g_context") do |dir|
      provider = FakeProvider.new
      ledger = AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json"))
      service = AiWorkspace::ContextReplyGeneration.new(ledger: ledger,
        provider_factory: ->(_key) { provider })
      baseline = Message.count
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-fake-key-for-test") do
          response = service.call(actor: @alice, room: @room,
            request_id: SecureRandom.uuid, confirmed: "1", hint: "Keep the reply brief.")
          assert_equal "Could you clarify the agreed deadline?", response.text
          assert_equal [@question.id], response.source_ids
          assert_equal "Keep the reply brief.", provider.hint
          assert_equal 1, provider.calls
          assert_equal 500_000, response.cost_ticks
        end
      end
      assert_equal baseline, Message.count
      charges = JSON.parse(File.read(File.join(dir, "ledger.json"))).fetch("entries").values
      assert_equal [500_000], charges.map { |value| value.fetch("charged_ticks") }
    end
  end

  test "no consent or revoked peer denies before reservation and provider" do
    grant(@alice)
    Dir.mktmpdir("h3g_closed") do |dir|
      path = File.join(dir, "ledger.json")
      service = AiWorkspace::ContextReplyGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path))
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        assert_raises(AiWorkspace::Errors::ConsentRequired) do
          service.call(actor: @alice, room: @room,
            request_id: SecureRandom.uuid, confirmed: "1")
        end
        assert_raises(AiWorkspace::Errors::ConsentRequired) do
          service.call(actor: @alice, room: @room,
            request_id: SecureRandom.uuid, confirmed: "0")
        end
      end
      assert_not File.exist?(path)
    end
  end

  test "long or sensitive user hints fail without spending" do
    grant(@alice)
    grant(@bob)
    Dir.mktmpdir("h3g_hint") do |dir|
      path = File.join(dir, "ledger.json")
      service = AiWorkspace::ContextReplyGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path))
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        ["x" * 701, "unsafe@example.test", "sk-proj-abcdefghijklmnopqrstuvwxyz"].each do |hint|
          assert_raises(AiWorkspace::Errors::InvalidSelection) do
            service.call(actor: @alice, room: @room,
              request_id: SecureRandom.uuid, confirmed: "1", hint: hint)
          end
        end
      end
      assert_not File.exist?(path)
    end
  end

  test "provider is fail closed by default in test and production" do
    assert_not AiWorkspace::ContextReplyGeneration.enabled?
  end
  test "selected evidence is the only provider context, while stale selection costs nothing" do
    grant(@alice)
    grant(@bob)
    @room.messages.create!(user: @bob, body: "Unrelated contract clause.")
    context = AiWorkspace::ReplyContextBuilder.new.build(room: @room, actor: @alice)
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: context, hint: "")
    Dir.mktmpdir("h3g_selected_reply") do |dir|
      path = File.join(dir, "ledger.json")
      provider = FakeProvider.new
      service = AiWorkspace::ContextReplyGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path),
        provider_factory: ->(_key) { provider })
      before = Message.count
      AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
        assert_raises(AiWorkspace::Errors::InvalidSelection) do
          service.call(actor: @alice, room: @room, confirmed: "1", hint: "",
            request_id: SecureRandom.uuid, source_token: token,
            selected_ids: [99_999_999])
        end
        assert_not File.exist?(path)
        assert_equal 0, provider.calls
        ENV.stub(:fetch, "xai-fake-key-for-test") do
          result = service.call(actor: @alice, room: @room, confirmed: "1",
            request_id: SecureRandom.uuid, source_token: token,
            selected_ids: [@question.id])
          assert_equal [@question.id], result.source_ids
          assert_equal [@question.id], provider.bundle.source_ids
          assert_equal 1, provider.calls
        end
      end
      assert_equal before, Message.count
    end
  end

end
