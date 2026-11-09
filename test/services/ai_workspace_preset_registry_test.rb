require "test_helper"
require "tempfile"
require "yaml"

class AiWorkspacePresetRegistryTest < ActiveSupport::TestCase
  def yaml_from_registry
    YAML.safe_load(File.read(AiWorkspace::PresetRegistry::BUNDLED_PATH))
  end

  def check_bad_yaml(content)
    Tempfile.create(["unsafe-ai-presets", ".yml"]) do |file|
      file.write(content)
      file.flush
      error = assert_raises(AiWorkspace::Errors::InvalidPreset) do
        AiWorkspace::PresetRegistry.new(path: file.path)
      end
      assert_match(/Invalid preset/, error.message)
      assert_not_includes error.message, "UNTRUSTED_MARKER"
    end
  end

  test "six bundled presets are immutable, versioned and have compatible operations" do
    registry = AiWorkspace::PresetRegistry.bundled
    expected = AiWorkspace::PresetRegistry::EXPECTED_IDS
    assert_equal expected, registry.all.map(&:id)
    assert_equal 6, registry.all.size
    assert registry.all.frozen?
    assert_equal 3, registry.for_operation("beautify").size
    assert_equal 1, registry.for_operation("translate").size
    assert_equal 1, registry.for_operation("summarize").size
    assert_equal 1, registry.for_operation("suggest_reply").size

    registry.all.each do |preset|
      assert preset.frozen?
      assert preset.snapshot.frozen?
      assert_equal 1, preset.version
      assert_equal 1, preset.snapshot.fetch("schema_version")
      assert_equal "manual", preset.snapshot.dig("context", "policy")
      assert_equal true, preset.snapshot.dig("constraints", "preserve_facts")
      assert_equal true, preset.snapshot.dig("constraints", "require_user_approval")
      assert_equal 1, preset.snapshot.dig("output", "variants")
      assert_same preset, registry.fetch(preset.id)
    end
    assert_raises(AiWorkspace::Errors::InvalidPreset) { registry.fetch("non_existing") }
    assert_raises(AiWorkspace::Errors::InvalidPreset) { registry.fetch(nil) }
    assert_raises(FrozenError) { registry.all.clear }
  end

  test "strict registry rejects duplicates, incompatible versions and injected keys" do
    cases = []
    duplicated = yaml_from_registry
    duplicated[1]["id"] = duplicated[0]["id"]
    cases << duplicated
    invalid_version = yaml_from_registry
    invalid_version[0]["schema_version"] = 2
    cases << invalid_version
    invalid_operation = yaml_from_registry
    invalid_operation[0]["operation"] = "external_http"
    cases << invalid_operation
    injected = yaml_from_registry
    injected[0]["system_prompt"] = "UNTRUSTED_MARKER"
    cases << injected
    missing = yaml_from_registry
    missing[0].delete("constraints")
    cases << missing
    forbidden_rule = yaml_from_registry
    forbidden_rule[0]["constraints"]["require_user_approval"] = false
    cases << forbidden_rule

    cases.each { |data| check_bad_yaml(YAML.dump(data)) }
  end

  test "unsafe YAML aliases, objects, unknown shape and oversized files fail closed" do
    check_bad_yaml("--- !ruby/object:OpenStruct\nUNTRUSTED_MARKER: true\n")
    check_bad_yaml("---\n- &a {id: test}\n- *a\n")
    check_bad_yaml("---\nUNTRUSTED_MARKER: value\n")
    check_bad_yaml("x" * (AiWorkspace::PresetRegistry::MAX_BYTES + 1))
  end
end
