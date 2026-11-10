require "test_helper"

class AiWorkspaceConversationTaskV1Test < ActiveSupport::TestCase
  test "five tasks are strict, versioned and contain no user-provided system prompts" do
    assert_equal 1, AiWorkspace::ConversationTaskV1::VERSION
    assert_equal %w[
      action_items client_brief client_proposal content_outline conversation_summary
    ], AiWorkspace::ConversationTaskV1::TASKS.keys.sort
    AiWorkspace::ConversationTaskV1::TASKS.each_key do |name|
      config = AiWorkspace::ConversationTaskV1.fetch!(name)
      assert config.frozen?
      assert_includes config[:system], "untrusted data"
      assert_includes config[:system].downcase, "only"
      assert_operator config[:max_output_tokens], :<=, 750
    end
    ["model_prompt", "delete_db", "autopublish", nil, 1].each do |bad|
      assert_raises(AiWorkspace::Errors::InvalidSelection) do
        AiWorkspace::ConversationTaskV1.fetch!(bad)
      end
    end
  end

  test "context task payload carries only approved source markers and a capped author note" do
    row = AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: 123, speaker: "participant_2",
      text: "Please review the client request.", truncated: false
    )
    bundle = AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 1, actor_id: 2, rows: [row],
      source_ids: [123], characters: row.text.length, omitted: 0
    )
    content = AiWorkspace::ConversationTaskV1.user_input(
      bundle: bundle, kind: "client_brief", hint: "Use a business tone."
    )
    payload = JSON.parse(content)
    assert_equal "client_brief", payload.fetch("task")
    assert_equal "M123", payload.fetch("excerpts").first.fetch("ref")
    assert_equal "Use a business tone.", payload.fetch("author_note")
    assert_not_includes content, "password"
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::ConversationTaskV1.user_input(
        bundle: bundle, kind: "client_brief", hint: "x" * 1000
      )
    end
  end
end
