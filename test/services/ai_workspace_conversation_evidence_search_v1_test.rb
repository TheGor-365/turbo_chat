require "test_helper"
require "securerandom"

class AiWorkspaceConversationEvidenceSearchV1Test < ActiveSupport::TestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    [@alice, @bob].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: user).grant!
    end
  end

  test "classifies cues conservatively and respects explicit negation" do
    classify = AiWorkspace::EvidenceSignalClassifierV1.method(:call)
    assert_equal "proposal", classify.call("Предлагаю сроки проекта на март")[:state]
    assert_equal "confirmation_candidate", classify.call("Согласовано: сроки проекта март")[:state]
    assert_equal "revocation_candidate", classify.call("Отменяем сроки проекта на март")[:state]
    assert_equal "rejection_candidate", classify.call("Не согласовано: сроки проекта на март")[:state]
    assert_equal "rejection_candidate", classify.call("Not approved for March")[:state]
    assert_equal "mixed_requires_review", classify.call("Предлагаю и подтверждаю новые сроки")[:state]
    assert_equal "undetermined", classify.call("The draft schedule is on the shared board")[:state]
    assert_equal "rule_only_unverified", classify.call("Approved")[:confidence]
  end

  test "searches historical safe sources and marks opposing cues as possible only" do
    proposal = @room.messages.create!(user: @alice,
      body: "Предлагаю сроки проекта на март, подготовить спецификацию")
    confirmation = @room.messages.create!(user: @bob,
      body: "Согласовано: сроки проекта на март, подготовить спецификацию")
    revocation = @room.messages.create!(user: @alice,
      body: "Отменяем сроки проекта на март, подготовить спецификацию")
    unrelated = @room.messages.create!(user: @bob, body: "Weather today is cloudy")
    before = Message.count

    result = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "сроки проекта"
    )
    assert_equal 1, result[:version]
    assert_equal "local_lexical_evidence_candidates_not_ai", result[:state]
    assert_equal 4, result.dig(:source_inventory, :total_messages)
    assert_equal [proposal.id, confirmation.id, revocation.id].sort,
      result[:results].map { |item| item[:id] }.sort
    assert_not_includes result[:results].map { |item| item[:id] }, unrelated.id
    assert_equal "all_candidates_require_human_verification", result[:review]
    assert_equal true, result.dig(:retrieval, :not_an_exhaustive_semantic_search)
    pair = result[:possible_conflicts].find { |item|
      item[:source_ids] == [confirmation.id, revocation.id].sort
    }
    assert pair, result[:possible_conflicts].inspect
    assert_equal "possible_conflict_requires_review", pair[:state]
    assert_equal before, Message.count
    assert_operator result[:results].first[:excerpt].length, :<=, 242
    assert_nil result[:results].first[:text]
  end

  test "excluded and former-member texts remain outside matches" do
    safe = @room.messages.create!(user: @bob, body: "Rails issue: stale session cookie")
    sensitive = @room.messages.create!(user: @alice,
      body: "Rails issue: send credentials to secret@example.org")
    third = User.create!(email: "fcc2d-former@example.test", password: "secure-password-123")
    @room.participants.create!(user: third)
    former = @room.messages.create!(user: third,
      body: "Rails issue: former member secret")
    @room.participants.where(user: third).delete_all

    result = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "Rails issue"
    )
    assert_equal [safe.id], result[:results].map { |item| item[:id] }
    assert_equal 2, result.dig(:source_inventory, :excluded_messages)
    serialized = result.to_json
    assert_not_includes serialized, sensitive.body
    assert_not_includes serialized, former.body
  end

  test "concurrent body mutation without timestamp update invalidates search" do
    target = @room.messages.create!(user: @bob,
      body: "Согласовано: сроки проекта на март")
    snapshot = Class.new do
      define_method(:initialize) { |target:|
        @target, @count = target, 0
      }
      define_method(:build) { |room:, actor:|
        @count += 1
        @target.update_columns(body: "Отменяем сроки проекта на апрель") if @count == 2
        AiWorkspace::ConversationCoverageSnapshotV2.new.build(room: room, actor: actor)
      }
    end.new(target: target)

    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationEvidenceSearchV1.new(snapshot: snapshot).call(
        room: @room, actor: @alice, query: "сроки проекта"
      )
    end
  end

  test "rejects secret queries, oversized queries, and meaningless terms" do
    search = AiWorkspace::ConversationEvidenceSearchV1.new
    ["", "ab", "  ", "and for from", "secret@example.test",
      "sk-proj-" + "x" * 24, "x" * 121].each do |query|
      assert_raises(AiWorkspace::Errors::InvalidSelection, query.inspect) do
        search.call(room: @room, actor: @alice, query: query)
      end
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      search.call(room: @room, actor: @alice, query: { text: "Rails" })
    end
  end

  test "revoked consent aborts the entire search" do
    @room.messages.create!(user: @bob, body: "Rails issue")
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    assert_raises(AiWorkspace::Errors::ConsentRequired) do
      AiWorkspace::ConversationEvidenceSearchV1.new.call(
        room: @room, actor: @alice, query: "Rails"
      )
    end
  end

  test "chronology describes source order and never converts cue into approved decision" do
    proposed = @room.messages.create!(user: @alice,
      body: "Предлагаю сроки проекта на март")
    accepted = @room.messages.create!(user: @bob,
      body: "Согласовано: сроки проекта на март")
    withdrawn = @room.messages.create!(user: @alice,
      body: "Отменяем сроки проекта на март")
    result = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "сроки проекта"
    )
    timeline = result.fetch(:chronology)
    assert_equal "unverified_candidate_chronology", timeline.fetch(:state)
    assert_equal "not_determined", timeline.fetch(:approval_state)
    assert_equal [proposed.id, accepted.id, withdrawn.id],
      timeline.fetch(:events).map { |event| event.fetch(:id) }
    speakers = timeline.fetch(:events).map { |event| event.fetch(:speaker) }
    assert_equal "you", speakers[0]
    assert_match(/\Aparticipant_[1-9]\d?\z/, speakers[1])
    assert_equal "you", speakers[2]
    assert_equal %w[possible_response_to_proposal possible_reversal],
      timeline.fetch(:links).map { |edge| edge.fetch(:relation) }
    assert timeline.fetch(:events).all? { |event|
      event.fetch(:created_at).end_with?("Z")
    }
    assert_not result.key?(:approved_decision)
    assert_equal 3, @room.messages.count
  end

  test "post-snapshot creation-time mutation without body or updated_at change fails closed" do
    target = @room.messages.create!(user: @bob,
      body: "Согласовано: сроки проекта на март")
    original = target.created_at
    snapshot = Class.new do
      define_method(:initialize) { |target:| @target, @calls = target, 0 }
      define_method(:build) { |room:, actor:|
        @calls += 1
        @target.update_columns(created_at: @target.created_at - 1.day) if @calls == 2
        AiWorkspace::ConversationCoverageSnapshotV2.new.build(room: room, actor: actor)
      }
    end.new(target: target)

    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationEvidenceSearchV1.new(snapshot: snapshot).call(
        room: @room, actor: @alice, query: "сроки проекта"
      )
    end
    assert_operator target.reload.created_at, :<, original
  end

  test "chronology explicitly covers only the twelve returned ranked matches" do
    15.times { |index|
      @room.messages.create!(user: @bob, body: "Rails milestone topic #{index}")
    }
    result = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "Rails milestone"
    )
    assert_equal 12, result.fetch(:results).size
    assert_equal 12, result.dig(:chronology, :events).size
    assert_equal "selected_ranked_matches_only", result.dig(:chronology, :scope)
    assert_equal "not_determined", result.dig(:chronology, :approval_state)
    assert_equal 15, result.dig(:retrieval, :scanned_matching_rows)
  end

  test "search reports only own stance bound to the exact current source version" do
    target = @room.messages.create!(user: @bob,
      body: "Rails roadmap milestone 14 days")
    first = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "Rails roadmap"
    )
    token = first.fetch(:results).first.fetch(:source_version)
    assert_match(/\A[0-9a-f]{64}\z/, token)
    assert_equal "none", first.fetch(:results).first.fetch(:personal_stance)

    AiWorkspace::EvidenceReviewRecorderV1.new.call(room: @room,
      actor: @alice, message_id: target.id.to_s,
      source_version: token, stance: "acknowledged",
      request_key: SecureRandom.uuid)
    second = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "Rails roadmap"
    )
    assert_equal "acknowledged", second.fetch(:results).first.fetch(:personal_stance)

    other = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @bob, query: "Rails roadmap"
    )
    assert_equal "none", other.fetch(:results).first.fetch(:personal_stance)

    target.update!(body: "Rails roadmap milestone 30 days")
    changed = AiWorkspace::ConversationEvidenceSearchV1.new.call(
      room: @room, actor: @alice, query: "Rails roadmap"
    )
    assert_equal "none", changed.fetch(:results).first.fetch(:personal_stance)
    assert_not_equal token, changed.fetch(:results).first.fetch(:source_version)
    assert_equal 1, AiEvidenceReviewEvent.where(room: @room).count
  end
end
