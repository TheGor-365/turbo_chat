require "test_helper"

class AiWorkspaceSavedRevisionDiffV1Test < ActiveSupport::TestCase
  test "compares exact added, removed and unchanged lines without semantic inference" do
    result = AiWorkspace::SavedRevisionDiffV1.compare!(
      before: "## Objective\n- Price: To confirm\n## Requirements",
      after: "## Objective\n- Price: Awaiting reply\n## Requirements"
    )
    assert_equal [1, 1, 2], [result.added, result.removed, result.unchanged]
    assert_equal ["added", "removed", "unchanged", "unchanged"].sort,
      result.rows.map(&:status).sort
    assert_includes result.rows.map(&:text), "- Price: To confirm"
    assert_includes result.rows.map(&:text), "- Price: Awaiting reply"
  end

  test "unchanged versions have no false changes" do
    result = AiWorkspace::SavedRevisionDiffV1.compare!(
      before: "## Summary\n- Same [M3]", after: "## Summary\n- Same [M3]"
    )
    assert_equal [0, 0, 2], [result.added, result.removed, result.unchanged]
  end

  test "diff rejects unbounded input" do
    assert_raises(ArgumentError) do
      AiWorkspace::SavedRevisionDiffV1.compare!(before: "x" * 5001, after: "ok")
    end
    assert_raises(ArgumentError) do
      AiWorkspace::SavedRevisionDiffV1.compare!(before: "x\n" * 161, after: "ok")
    end
  end
end
