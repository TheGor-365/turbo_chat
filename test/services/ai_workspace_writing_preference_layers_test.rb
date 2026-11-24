require "test_helper"

class AiWorkspaceWritingPreferenceLayersTest < ActiveSupport::TestCase
  def snapshot(language)
    { profile_id: "universal", writing_style: "polish_clarity",
      language: language, tone: "neutral" }
  end

  test "system account shared and personal precedence with reset" do
    resolver = AiWorkspace::WritingPreferenceLayers
    assert_equal "system", resolver.resolve.source
    account = snapshot("en")
    shared = snapshot("hy")
    personal = snapshot("ru")
    assert_equal "en", resolver.resolve(account: account).effective[:language]
    assert_equal "hy", resolver.resolve(account: account, shared: shared).effective[:language]
    assert_equal "ru", resolver.resolve(account: account, shared: shared, personal: personal).effective[:language]
    shared[:language] = "es"
    assert_equal "ru", resolver.resolve(account: account, shared: shared, personal: personal).effective[:language]
    reset = resolver.resolve(account: account, shared: shared)
    assert_equal "es", reset.effective[:language]
    assert_equal "shared", reset.origins[:language]
    assert_equal "ru", personal[:language]
  end

  test "legacy nil profile survives and returned values are independent immutable copies" do
    personal = snapshot("ru").merge(profile_id: nil)
    result = AiWorkspace::WritingPreferenceLayers.resolve(personal: personal)
    assert_nil result.effective[:profile_id]
    assert result.frozen?
    assert result.effective.frozen?
    assert result.effective[:language].frozen?
    personal[:language] = "en"
    assert_equal "ru", result.effective[:language]
  end

  test "unknown fields partial snapshots invalid values and mismatched profile are rejected" do
    resolver = AiWorkspace::WritingPreferenceLayers
    [snapshot("xx"), snapshot("en").merge(enabled: true),
      { language: "en" }, snapshot("en").merge(profile_id: "business")].each do |bad|
      assert_raises(AiWorkspace::Errors::InvalidPreset) { resolver.resolve(shared: bad) }
    end
  end
end
