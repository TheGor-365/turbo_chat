require "test_helper"

class H3gSchemaPreflightScriptTest < ActiveSupport::TestCase
  test "migration preflight parses as bash and stays read-only" do
    path = Rails.root.join("bin/h3g_schema_preflight.sh")
    script = File.read(path)
    assert system("bash", "-n", path.to_s)
    assert_includes script, "BEGIN READ ONLY"
    assert_includes script, "git status --short -- db/schema.rb"
    assert_match(/--read-only/, script)
    assert_no_match(/\bdocker compose (?:up|down|restart|run|rm)\b/, script)
    assert_no_match(/\b(?:db:reset|db:drop|db:schema:load|db:migrate)\b/, script)
    assert_no_match(/\b(?:git reset|git checkout --|git clean)\b/, script)
  end
end
