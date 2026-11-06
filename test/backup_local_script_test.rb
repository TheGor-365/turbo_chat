require "test_helper"

class BackupLocalScriptTest < ActiveSupport::TestCase
  test "local backup shell script parses and is not an automatic restore" do
    script = Rails.root.join("bin/backup_local.sh")
    assert File.file?(script)
    assert system("bash", "-n", script.to_s), "backup script must have valid Bash syntax"
    source = File.read(script)
    assert_includes source, "pg_dump"
    assert_includes source, "pg_restore --list"
    assert_includes source, "active_storage.tar.gz"
    assert_includes source, "sha256sum --check"
    assert_no_match(/pg_restore\s+--clean|db:reset|compose down -v/, source)
  end

  test "backup validation never extracts archives or restores into any database" do
    script = Rails.root.join("bin/verify_local_backup.sh")
    assert File.file?(script)
    assert system("bash", "-n", script.to_s), "validator must have valid Bash syntax"
    source = File.read(script)
    assert_includes source, "sha256sum --check"
    assert_includes source, "tar -tzf"
    assert_includes source, "pg_restore --list"
    assert_no_match(/pg_restore\s+--(dbname|clean)|pg_restore\s+-d|pg_restore\s+--create|tar\s+-x|compose down -v|db:reset/, source)
  end
  test "recovery drill only targets disposable network-isolated Docker and never local Compose DB" do
    script = Rails.root.join("bin/restore_drill_isolated.sh")
    assert File.file?(script)
    assert system("bash", "-n", script.to_s), "recovery drill must have valid Bash syntax"
    source = File.read(script)
    assert_includes source, "--isolated-restore-only"
    assert_includes source, "--network none"
    assert_includes source, "docker run --rm"
    assert_includes source, "pg_restore"
    assert_includes source, "handle.extractall(path=root, filter=\"data\")"
    assert_no_match(/docker compose.*(?:down|exec).*pg_restore|db:reset|pg_restore\s+--clean/, source)
  end

end
