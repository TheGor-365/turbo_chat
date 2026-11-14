require "test_helper"

class AiWorkspaceDraftPromptV1Test < ActiveSupport::TestCase
  test "all bundled prompts are versioned and source-owned" do
    assert_equal 1, AiWorkspace::DraftPromptV1::VERSION
    assert_equal AiWorkspace::PresetRegistry::EXPECTED_IDS.sort,
      AiWorkspace::DraftPromptV1::RULES.keys.sort
    AiWorkspace::PresetRegistry.bundled.all.each do |preset|
      target = preset.operation == "translate" ? "en" : nil
      prompt = AiWorkspace::DraftPromptV1.for(preset: preset, target_locale: target)
      assert prompt.frozen?
      assert_includes prompt, "untrusted data"
      assert_includes prompt, "Return only"
      assert_not_includes prompt, "Safe synthetic own draft"
    end
  end

  test "translation validates locale and nontranslation rejects target" do
    registry = AiWorkspace::PresetRegistry.bundled
    translate = registry.fetch("translate_preserving_tone")
    assert_includes AiWorkspace::DraftPromptV1.for(preset: translate, target_locale: "ru"), "Russian"
    assert_includes AiWorkspace::DraftPromptV1.for(preset: translate, target_locale: "hy"), "Armenian"
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::DraftPromptV1.for(preset: translate, target_locale: nil)
    end
    assert_raises(AiWorkspace::Errors::InvalidSelection) do
      AiWorkspace::DraftPromptV1.for(preset: registry.fetch("friendly"), target_locale: "en")
    end
    assert_raises(AiWorkspace::Errors::InvalidPreset) do
      AiWorkspace::DraftPromptV1.for(preset: Object.new)
    end
  end
end
