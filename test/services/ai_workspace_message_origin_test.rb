require "test_helper"

class AiWorkspaceMessageOriginTest < ActiveSupport::TestCase
  test "only an authenticated signed own draft proof determines edited origin" do
    actor = users(:one)
    room = rooms(:one)
    source = "Reviewed candidate"
    args = { actor: actor, room: room, source_text: source }
    token = AiWorkspace::DraftProvenance.issue(**args, workflow: "own_draft_edit")
    assert_equal "ai_edited", AiWorkspace::MessageOrigin.verified_ai(**args, token: token)
    assert_nil AiWorkspace::MessageOrigin.verified_ai(**args, token: "forged")
    assert_nil AiWorkspace::MessageOrigin.verified_ai(**args.merge(source_text: "different"), token: token)
    assert_nil AiWorkspace::MessageOrigin.verified_ai(**args.merge(actor: users(:two)), token: token)
    assert_nil AiWorkspace::MessageOrigin.verified_ai(**args.merge(room: rooms(:two)), token: token)
    travel_to 31.minutes.from_now do
      assert_nil AiWorkspace::MessageOrigin.verified_ai(**args, token: token)
    end
  end

  test "mapping preserves verified model synthetic and legacy distinctions" do
    expected = { "own_draft_edit" => "ai_edited", "model_answer" => "ai_generated",
      "synthetic_answer" => "synthetic", "answer_unclassified" => "ai_assisted_legacy",
      nil => nil, "forged" => nil, "manual" => nil }
    expected.each do |workflow, origin|
      AiWorkspace::DraftProvenance.stub(:verified_workflow, workflow) do
        actual = AiWorkspace::MessageOrigin.verified_ai(token: "fixture",
          actor: users(:one), room: rooms(:one), source_text: "fixture")
        origin.nil? ? assert_nil(actual) : assert_equal(origin, actual)
      end
    end
  end

  test "historical and contradictory records are not given invented origin" do
    policy = AiWorkspace::MessageOrigin
    assert_equal "unknown", policy.display_kind(origin: nil, ai_assisted: false)
    assert_equal "ai_assisted_legacy", policy.display_kind(origin: nil, ai_assisted: true)
    assert_equal "manual", policy.display_kind(origin: "manual", ai_assisted: false)
    %w[ai_edited ai_generated synthetic ai_assisted_legacy].each do |kind|
      assert_equal kind, policy.display_kind(origin: kind, ai_assisted: true)
      assert_equal "unknown", policy.display_kind(origin: kind, ai_assisted: false)
    end
    assert_equal "unknown", policy.display_kind(origin: "manual", ai_assisted: true)
    assert_equal "unknown", policy.display_kind(origin: "forged", ai_assisted: true)
    assert_equal "unknown", policy.display_kind(origin: "manual", ai_assisted: nil)
  end
end
