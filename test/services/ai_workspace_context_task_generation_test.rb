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
          assert_equal false, result.structured_review[:complete]
          assert_equal "unavailable", result.structured_review[:review_state]
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

  test "structured content is evaluated offline after provider call without auto approval" do
    Dir.mktmpdir("h4_structured") do |dir|
      provider = FakeProvider.new
      provider.define_singleton_method(:generate_context_task!) do |bundle, kind:, hint:|
        @calls += 1
        first = bundle.source_ids.first
        AiWorkspace::Providers::XaiResponses::Result.new(
          text: [
            "## Objective", "- Diagnose checkout error [M#{first}]",
            "## Requirements", "- Review Rails validation [M#{first}]",
            "## Constraints", "- Constraints: To confirm",
            "## Deliverables", "- Deliverables: To confirm",
            "## Acceptance Criteria", "- Acceptance: To confirm",
            "## Open Questions", "- Deadline: To confirm"
          ].join("\n"),
          model: "grok-4.3", input_tokens: 155, output_tokens: 120,
          cost_in_usd_ticks: 500_000
        )
      end
      service = AiWorkspace::ContextTaskGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(
          path: File.join(dir, "ledger.json")
        ), provider_factory: ->(_key) { provider }
      )
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "fake-key-not-real") do
          response = service.call(actor: @alice, room: @room, kind: "client_brief",
            confirmed: "1", request_id: SecureRandom.uuid)
          assert_equal true, response.structured_review[:complete]
          assert_equal "pending_manual_review", response.structured_review[:review_state]
          assert_empty response.structured_review[:warnings]
        end
      end
      assert_equal 1, provider.calls
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
  test "task model sees only chosen sources, not the full reviewed conversation" do
    @room.messages.create!(user: @bob, body: "Unrelated additional scope.")
    context = AiWorkspace::ReplyContextBuilder.new.build(room: @room, actor: @alice)
    token = AiWorkspace::SourceSelection.issue(
      room: @room, actor: @alice, bundle: context, hint: "")
    Dir.mktmpdir("h3g_selected_task") do |dir|
      provider = FakeProvider.new
      service = AiWorkspace::ContextTaskGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: File.join(dir, "ledger.json")),
        provider_factory: ->(_key) { provider })
      before = Message.count
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "fake-key-not-real") do
          result = service.call(actor: @alice, room: @room, kind: "client_brief",
            confirmed: "1", request_id: SecureRandom.uuid,
            source_token: token, selected_ids: [@message.id])
          assert_equal [@message.id], provider.bundle.source_ids
          assert_equal [@message.id], result.source_ids
          assert_includes result.text, "[M#{@message.id}]"
          assert_equal 1, provider.calls
          assert_equal [@message.id], result.evidence_review[:cited_source_ids]
          assert_equal 1, result.evidence_review[:linked_lines]
        end
      end
      assert_equal before, Message.count
    end
  end


  %w[revoke regrant edit delete].each do |change|
    test "rejects #{change} during inference but settles measured charge" do
      [@alice, @bob].each do |user|
        AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
      end
      grant = AiRoomContextConsent.find_by!(room: @room, user: @bob)
      source = @message
      room = @room
      actor = @alice
      mutate = lambda do
        case change
        when "revoke"
          grant.revoke!
        when "regrant"
          grant.revoke!
          grant.grant!
        when "edit"
          source.update!(body: "The scope and deadline have changed.")
        when "delete"
          source.destroy!
        end
      end
      provider = FakeProvider.new
      original = provider.method(:generate_context_task!)
      provider.define_singleton_method(:generate_context_task!) do |bundle, **options|
        result = original.call(bundle, **options)
        mutate.call
        result
      end
      Dir.mktmpdir("pai_transport") do |dir|
        path = File.join(dir, "ledger.json")
        ledger = AiWorkspace::LocalBudgetLedger.new(path: path)
        service = AiWorkspace::ContextTaskGeneration.new(ledger: ledger,
          provider_factory: ->(_key) { provider })
        before = Message.count
        AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
          ENV.stub(:fetch, "xai-fake-key-for-test") do
            error = %w[revoke regrant].include?(change) ?
              AiWorkspace::Errors::ConsentRequired : AiWorkspace::Errors::InvalidSelection
            assert_raises(error) do
              service.call(actor: actor, room: room, kind: "client_brief", request_id: SecureRandom.uuid,
                confirmed: "1")
            end
          end
        end
        assert_equal 1, provider.calls
        assert_equal before - (change == "delete" ? 1 : 0), Message.count
        charges = JSON.parse(File.read(path)).fetch("entries").values
        assert_equal [500_000], charges.map { |entry| entry.fetch("charged_ticks") }
      end
    end
  end


  test "independent transport excludes ungranted own history and keeps manual request semantics" do
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: @bob).grant!
    AiRoomContextConsent.find_or_initialize_by(room: @room, user: @alice).revoke!
    own = @room.messages.create!(user: @alice, body: "Withheld internal project note")
    access = AiWorkspace::RoomContextAccess::Independent.new
    bundle = AiWorkspace::ReplyContextBuilder.new(access: access).build(room: @room, actor: @alice)
    token = AiWorkspace::SourceSelection.issue(room: @room, actor: @alice,
      bundle: bundle, hint: "", access: access)
    Dir.mktmpdir("pai_independent_task") do |dir|
      path = File.join(dir, "ledger.json")
      provider = FakeProvider.new
      service = AiWorkspace::ContextTaskGeneration.new(access: access,
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path),
        provider_factory: ->(_key) { provider })
      before = Message.count
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-test-no-network") do
          result = service.call(actor: @alice, room: @room, kind: "client_brief", confirmed: "1",
            request_id: SecureRandom.uuid, source_token: token, selected_ids: [@message.id])
          assert_equal [@message.id], result.source_ids
          assert_equal [@message.id], provider.bundle.source_ids
          assert_not_includes provider.bundle.rows.map(&:text), own.body
          assert_equal 1, provider.calls
          AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
          assert_raises(AiWorkspace::Errors::InvalidSelection) do
            service.call(actor: @alice, room: @room, kind: "client_brief", confirmed: "1",
              request_id: SecureRandom.uuid, source_token: token, selected_ids: [@message.id])
          end
          assert_equal 1, provider.calls
        end
      end
      assert_equal before, Message.count
      charges = JSON.parse(File.read(path)).fetch("entries").values
      assert_equal [500_000], charges.map { |entry| entry.fetch("charged_ticks") }
    end
  end

  test "personal OFF denies before reservation and OFF ON during transport withholds billed output" do
    policy = AiWorkspace::PersonalEnablement
    policy.write(actor: @alice, enabled: false, expected_revision: 0)
    Dir.mktmpdir("personal_context_gate") do |dir|
      path = File.join(dir, "ledger.json")
      provider = FakeProvider.new
      actor = @alice
      original = provider.method(:generate_context_task!)
      provider.define_singleton_method(:generate_context_task!) do |bundle, **options|
        result = original.call(bundle, **options)
        policy.write(actor: actor, enabled: false, expected_revision: 2)
        policy.write(actor: actor, enabled: true, expected_revision: 3)
        result
      end
      service = AiWorkspace::ContextTaskGeneration.new(
        ledger: AiWorkspace::LocalBudgetLedger.new(path: path),
        provider_factory: ->(_key) { provider })
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        ENV.stub(:fetch, "xai-fixture-no-network") do
          args = {actor: @alice, room: @room, confirmed: "1", kind: "client_brief"}
          assert_raises(AiWorkspace::Errors::ConsentRequired) do
            service.call(**args, request_id: SecureRandom.uuid)
          end
          assert_not File.exist?(path)
          assert_equal 0, provider.calls
          policy.write(actor: @alice, enabled: true, expected_revision: 1)
          assert_raises(AiWorkspace::Errors::InvalidSelection) do
            service.call(**args, request_id: SecureRandom.uuid)
          end
          assert_equal 1, provider.calls
        end
      end
      charges = JSON.parse(File.read(path)).fetch("entries").values
      assert_equal [500_000], charges.map { |entry| entry.fetch("charged_ticks") }
    end
  end
end
