# frozen_string_literal: true
require "test_helper"

class AiWorkspaceSmartWorkflowV1Test < ActiveSupport::TestCase
  def bundle(incoming, older: nil)
    rows = []
    rows << AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: 7, speaker: "participant_1", text: older, truncated: false) if older
    rows << AiWorkspace::ReplyContextBuilder::Row.new(
      message_id: 8, speaker: "participant_1", text: incoming, truncated: false)
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 1, actor_id: 2, rows: rows.freeze,
      source_ids: rows.map(&:message_id).freeze,
      characters: rows.sum { |r| r.text.length }, omitted: 0).freeze
  end

  test "four-language advisory workflow selection" do
    samples = {
      "client_brief" => [
        "Please prepare a client brief.", "Нужно техническое задание.",
        "Preparar requisitos del proyecto.", "Պատրաստել հաճախորդի բրիֆ"
      ],
      "action_items" => [
        "Summarize next steps.", "Сделать список задач.",
        "Anotar próximos pasos.", "Նշեք հաջորդ քայլեր"
      ],
      "client_proposal" => [
        "Draft a commercial offer.", "Подготовить коммерческое предложение.",
        "Escribir una propuesta comercial.", "Կազմել առևտրային առաջարկ"
      ],
      "content_outline" => [
        "Write a content plan.", "Подготовить контент-план.",
        "Crear un plan de contenido.", "Ստեղծել բովանդակության պլան"
      ]
    }
    samples.each do |kind, examples|
      examples.each do |input|
        result = AiWorkspace::SmartWorkflowV1.suggest(bundle: bundle(input))
        assert_equal kind, result.kind, input
        assert_equal AiWorkspace::SmartWorkflowV1::STYLE_BY_KIND.fetch(kind),
          result.style_id, input
        assert_equal 1, result.version
        assert result.frozen?
      end
    end
  end

  test "defaults to conservative summary without guessing from older messages" do
    result = AiWorkspace::SmartWorkflowV1.suggest(
      bundle: bundle("Please check Rails validations.",
        older: "Last month we discussed a commercial offer."))
    assert_equal "conversation_summary", result.kind
    assert_equal "technical_summary", result.style_id
    result = AiWorkspace::SmartWorkflowV1.suggest(
      bundle: bundle("How are things going?"), hint: "Please outline next steps")
    assert_equal "action_items", result.kind
    assert_includes AiWorkspace::ConversationTaskV1::TASKS.keys, result.kind
  end
end
