require "test_helper"

class AiWorkspaceEvidenceReviewV1Test < ActiveSupport::TestCase
  def bundle(*texts)
    rows = texts.each_with_index.map do |text, i|
      AiWorkspace::ReplyContextBuilder::Row.new(
        message_id: 29 + i, speaker: "participant_1",
        text: text, truncated: false
      ).freeze
    end
    AiWorkspace::ReplyContextBuilder::Bundle.new(
      version: 1, room_id: 3, actor_id: 4, rows: rows.freeze,
      source_ids: rows.map(&:message_id).freeze,
      characters: texts.sum(&:length), omitted: 0
    ).freeze
  end

  test "matrix: sourced, unsourced, unknown and low-overlap lines" do
    report = AiWorkspace::EvidenceReviewV1.inspect!(
      text: "## Client brief\n- Review Rails validation [M29]\n" \
        "- Launch tomorrow is approved\n- Budget: To confirm\n" \
        "- Completely unrelated gardening instructions [M29]",
      bundle: bundle("Rails validation fails with HTTP 422.")
    )
    assert_equal "structural_only_not_fact_checked", report[:assessment]
    assert_equal 4, report[:checked_lines]
    assert_equal 2, report[:linked_lines]
    assert_equal 2, report[:uncited_lines]
    assert_equal 1, report[:needs_confirmation_lines]
    assert_equal 1, report[:weak_overlap_lines]
    assert_equal [29], report[:cited_source_ids]
    assert report.frozen?
  end

  test "matrix: Russian and Armenian with explicit uncertainty" do
    report = AiWorkspace::EvidenceReviewV1.inspect!(
      text: "Проверить Rails валидации [M29]\n" \
        "Ստուգել հաշվետվություն [M30]\nСроки нужно уточнить",
      bundle: bundle("Rails ошибка валидации", "Ստուգել հաշվետվություն")
    )
    assert_equal 2, report[:linked_lines]
    assert_equal 1, report[:needs_confirmation_lines]
    assert_equal 0, report[:weak_overlap_lines]
  end

  test "matrix: forged, wrong room or malformed references rejected" do
    ["Unknown [M31]", "Bad [M0]", "Bad [Mabc]", "Bad [M999999999999999999999]"].each do |text|
      assert_raises(AiWorkspace::Errors::ProviderUnavailable) do
        AiWorkspace::EvidenceReviewV1.inspect!(text: text, bundle: bundle("Rails question."))
      end
    end
  end

  test "matrix: lexical overlap cannot prove a negated assertion" do
    report = AiWorkspace::EvidenceReviewV1.inspect!(
      text: "Rails validation was not a problem [M29]",
      bundle: bundle("Rails validation was a problem.")
    )
    assert_equal 1, report[:linked_lines]
    assert_equal "structural_only_not_fact_checked", report[:assessment]
  end

  test "matrix: questions and code fences do not become claims or citations" do
    fence = 96.chr * 3
    body = "# Plan\nWhich endpoint failed?\n" + fence +
      "\ncode = \"[M31]\"\n" + fence + "\n- Review endpoint [M29]"
    report = AiWorkspace::EvidenceReviewV1.inspect!(
      text: body, bundle: bundle("Review endpoint errors.")
    )
    assert_equal 2, report[:checked_lines]
    assert_equal 1, report[:linked_lines]
    assert_equal 0, report[:uncited_lines]
  end

  test "matrix: report is bounded and never echoes source content" do
    private_text = "Private commercial Rails contract."
    report = AiWorkspace::EvidenceReviewV1.inspect!(
      text: Array.new(190, "- Uncited statement").join("\n"),
      bundle: bundle(private_text)
    )
    assert_equal 160, report[:checked_lines]
    assert_equal 20, report[:issues].size
    assert report[:truncated]
    assert_not_includes report.to_s, private_text
  end
end
