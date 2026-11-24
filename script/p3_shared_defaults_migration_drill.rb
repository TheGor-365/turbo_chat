# frozen_string_literal: true

# P3.1c: synthetic-only migration acceptance on a disposable CI PostgreSQL DB.
# Never run on the owner's database. The database and stored manifest are
# explicitly fenced by P3_DRILL_DB, RAILS_ENV=test and RUNNER_TEMP.
require "digest"
require "json"
require "fileutils"
require_relative "../config/environment"

class P3SharedDefaultsMigrationDrill
  BASELINE_TABLES = %w[
    users rooms participants messages ai_account_writing_preferences
    ai_room_writing_preferences ai_room_context_consents
  ].freeze
  NEW_TABLE = "ai_room_shared_writing_preferences"
  GROUP_NAME = "P3 synthetic migration drill"

  def initialize
    @connection = ActiveRecord::Base.connection
    @database = @connection.select_value("SELECT current_database()")
    expected = ENV.fetch("P3_DRILL_DB")
    unless Rails.env.test? && expected.start_with?("turbo_chat_p3_drill") &&
        @database == expected && ENV["RUNNER_TEMP"]&.start_with?("/")
      abort "P3 drill refused: requires an isolated CI test database."
    end
    @manifest = File.join(ENV.fetch("RUNNER_TEMP"), "#{expected}_baseline.json")
  end

  def run(stage)
    case stage
    when "seed" then seed!
    when "verify_up" then verify_up!
    when "verify_down" then verify_down!
    else abort "Usage: ruby script/p3_shared_defaults_migration_drill.rb seed|verify_up|verify_down"
    end
    puts "P3 synthetic migration drill #{stage}: PASS"
  end

  private

  def ensure!(condition, detail)
    abort "P3 synthetic migration drill FAIL: #{detail}" unless condition
  end

  def digest_for(table)
    quoted = @connection.quote_table_name(table)
    sql = "SELECT row_to_json(snapshot)::text FROM (SELECT * FROM #{quoted} ORDER BY id) snapshot"
    Digest::SHA256.hexdigest(JSON.generate(@connection.select_values(sql)))
  end

  def baseline
    BASELINE_TABLES.to_h { |table| [table, digest_for(table)] }
  end

  def ensure_baseline!
    saved = JSON.parse(File.read(@manifest))
    ensure!(baseline == saved.fetch("table_sha256"), "prior table contents changed")
    ensure!(saved.fetch("table_sha256").keys.sort == BASELINE_TABLES.sort, "incomplete baseline")
  end

  def seed!
    ensure!(!@connection.table_exists?(NEW_TABLE), "P3 migration already applied")
    ensure!(BASELINE_TABLES.all? { |table| @connection.table_exists?(table) },
      "baseline migration replay incomplete")
    owner = User.create!(email: "p3-drill-owner@example.test", password: "synthetic-password-123")
    member = User.create!(email: "p3-drill-member@example.test", password: "synthetic-password-123")
    room = Room.create!(name: GROUP_NAME, kind: "private_group", is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    room.participants.create!(user: member, group_role: "member")
    attrs = { profile_id: "universal", writing_style: "polish_clarity", tone: "neutral" }
    AiAccountWritingPreference.create!(user: member, **attrs, language: "es")
    AiRoomWritingPreference.create!(room: room, user: owner, **attrs, language: "ru")
    AiRoomWritingPreference.create!(room: room, user: member, **attrs, language: "hy")
    AiRoomContextConsent.find_or_initialize_by(room: room, user: member).grant!
    room.messages.create!(user: owner, body: "Synthetic owner statement.")
    room.messages.create!(user: member, body: "Synthetic incoming message.")
    File.write(@manifest, JSON.pretty_generate({ "table_sha256" => baseline }))
    File.chmod(0o600, @manifest)
  end

  def verify_up!
    ensure!(@connection.table_exists?(NEW_TABLE), "new table is absent")
    ensure_baseline!
    indexes = @connection.indexes(NEW_TABLE)
    ensure!(indexes.any? { |idx| idx.unique && idx.columns == ["room_id"] },
      "unique room index missing")
    foreign_keys = @connection.foreign_keys(NEW_TABLE)
    ensure!(foreign_keys.any? { |fk| fk.column == "room_id" && fk.to_table == "rooms" },
      "room FK missing")
    ensure!(foreign_keys.any? { |fk| fk.column == "editor_id" && fk.to_table == "users" },
      "editor FK missing")
    check = @connection.select_value(
      "SELECT count(*) FROM pg_constraint WHERE conname = 'shared_writing_preferences_nonnegative_lock'"
    ).to_i
    ensure!(check == 1, "lock version check constraint missing")
    ensure!(AiRoomSharedWritingPreference.count.zero?, "new table is not initially empty")

    room = Room.find_by!(name: GROUP_NAME)
    owner = User.find_by!(email: "p3-drill-owner@example.test")
    row = AiRoomSharedWritingPreference.create!(room: room, editor: owner,
      profile_id: "universal", writing_style: "polish_clarity",
      language: "en", tone: "neutral")
    ensure!(row.lock_version == 0 && row.revision == 1, "incorrect initial revision")
    ensure_baseline!
  end

  def verify_down!
    ensure!(!@connection.table_exists?(NEW_TABLE), "rollback failed to drop new table")
    ensure_baseline!
  end
end

P3SharedDefaultsMigrationDrill.new.run(ARGV.fetch(0))
