require "test_helper"

class LocalBackupArchiveStrategyTest < ActiveSupport::TestCase
  test "backup script archives root-owned private storage from the running web container" do
    path = Rails.root.join("bin/backup_local.sh")
    content = File.read(path)

    assert system("bash", "-n", path.to_s)
    assert_includes content, "docker compose exec -T web tar -czf - -C /app storage"
    assert_includes content, 'tar -tzf "$temporary/active_storage.tar.gz"'
    assert_includes content, "sha256sum --check --status SHA256SUMS"
    assert_includes content, 'docker compose ps --status running --services | grep -qx web'

    # The backup must not alter ownership/mode, skip the ledger, or silently
    # continue after a failed read. Only the private *temporary backup dir*
    # is removed by the existing EXIT trap.
    refute_match(/^\s*(?:sudo\s+)?(?:chmod|chown)\b/, content)
    refute_match(/--exclude[^\n]*ai_h3_local_budget/, content)
    assert_includes content, "set -euo pipefail"
    assert_includes content, "umask 077"
  end
end
