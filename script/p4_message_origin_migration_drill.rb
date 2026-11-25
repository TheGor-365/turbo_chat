# frozen_string_literal: true

# Synthetic-only disposable PostgreSQL drill. Never run on owner data.
require "digest"
require "json"
require_relative "../config/environment"

class P4MessageOriginMigrationDrill
  DATABASE = "turbo_chat_p4_drill_origin"
  TABLES = %w[users rooms participants messages ai_personal_enablements
    ai_room_context_consents ai_room_shared_writing_preferences].freeze
  ORIGINS = %w[ai_edited ai_generated ai_assisted_legacy synthetic].freeze

  def initialize
    @connection = ActiveRecord::Base.connection
    unless Rails.env.test? && ENV["GITHUB_ACTIONS"] == "true" &&
        ENV["P4_DRILL_DB"] == DATABASE &&
        @connection.select_value("SELECT current_database()") == DATABASE &&
        ENV["RUNNER_TEMP"]&.start_with?("/")
      abort "P4 drill refused: requires the isolated GitHub Actions database."
    end
    @manifest = File.join(ENV.fetch("RUNNER_TEMP"), "#{DATABASE}_baseline.json")
  end

  def run(stage)
    case stage
    when "seed" then seed!
    when "verify_up" then verify_up!
    when "verify_down" then verify_down!
    else abort "Unknown P4 drill stage"
    end
    puts "P4 message origin migration drill #{stage}: PASS"
  end

  private

  def ensure!(condition, detail)
    abort "P4 migration drill FAIL: #{detail}" unless condition
  end

  def origin_column
    @connection.columns("messages").find { |column| column.name == "origin" }
  end

  def baseline
    TABLES.to_h do |table|
      # Compare every old field, including IDs, timestamps, reply and AI flag.
      # Exclude only the newly added column, not any existing message content.
      columns = @connection.columns(table).map(&:name) - (table == "messages" ? ["origin"] : [])
      fields = columns.map { |name| @connection.quote_column_name(name) }.join(", ")
      quoted = @connection.quote_table_name(table)
      rows = @connection.select_values("SELECT row_to_json(snapshot)::text FROM (SELECT #{fields} FROM #{quoted} ORDER BY id) snapshot")
      [table, Digest::SHA256.hexdigest(JSON.generate(rows))]
    end
  end

  def ensure_baseline!
    ensure!(baseline == JSON.parse(File.read(@manifest)), "existing records changed")
  end

  def seed!
    ensure!(!origin_column, "origin already exists")
    owner = User.create!(email: "p4-drill-owner@example.test", password: "synthetic-password-123")
    member = User.create!(email: "p4-drill-member@example.test", password: "synthetic-password-123")
    room = Room.create!(name: "P4 isolated migration drill", kind: "private_group", is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    room.participants.create!(user: member, group_role: "member")
    first = room.messages.create!(user: owner, body: "Synthetic legacy manual row.", ai_assisted: false)
    room.messages.create!(user: member, body: "Synthetic legacy AI row.", ai_assisted: true, reply_to: first)
    AiWorkspace::PersonalEnablement.write(actor: member, enabled: false, expected_revision: 0)
    AiRoomContextConsent.find_or_initialize_by(room: room, user: owner).grant!
    File.write(@manifest, JSON.pretty_generate(baseline))
    File.chmod(0o600, @manifest)
  end

  def verify_up!
    column = origin_column
    ensure!(column && column.null && column.default.nil? && column.limit == 32, "unexpected origin column")
    ensure!(@connection.check_constraints("messages").any? { |c| c.name == "messages_origin_consistent" }, "constraint missing")
    ensure_baseline!
    ensure!(@connection.select_value("SELECT COUNT(*) FROM messages WHERE origin IS NOT NULL").to_i.zero?, "legacy origin fabricated")
    manual_id = @connection.select_value("SELECT id FROM messages WHERE NOT ai_assisted LIMIT 1").to_i
    ai_id = @connection.select_value("SELECT id FROM messages WHERE ai_assisted LIMIT 1").to_i
    ensure!(manual_id.positive? && ai_id.positive?, "missing baseline cases")
    # Test actual PostgreSQL writes inside savepoints; roll back all probes
    # so both prior row digests and the next rollback remain meaningful.
    [[manual_id, "manual"], [manual_id, nil], [ai_id, nil], *ORIGINS.map { |origin| [ai_id, origin] }].each do |id, origin|
      ActiveRecord::Base.transaction(requires_new: true) do
        @connection.execute("UPDATE messages SET origin = #{@connection.quote(origin)} WHERE id = #{id}")
        ensure!(@connection.select_value("SELECT origin FROM messages WHERE id = #{id}") == origin, "valid origin not retained")
        raise ActiveRecord::Rollback
      end
    end
    [[ai_id, "manual"], [manual_id, "ai_generated"], [manual_id, "ai_edited"], [manual_id, "synthetic"], [manual_id, "ai_assisted_legacy"], [ai_id, "forged"]].each do |id, origin|
      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          @connection.execute("UPDATE messages SET origin = #{@connection.quote(origin)} WHERE id = #{id}")
          raise ActiveRecord::Rollback
        end
      rescue ActiveRecord::StatementInvalid => error
        ensure!(error.cause.is_a?(PG::CheckViolation), "unexpected database error")
        next
      end
      abort "P4 migration drill FAIL: incompatible origin accepted"
    end
    ensure_baseline!
  end

  def verify_down!
    ensure!(!origin_column, "rollback retained origin column")
    ensure!(@connection.check_constraints("messages").none? { |c| c.name == "messages_origin_consistent" }, "rollback retained constraint")
    ensure_baseline!
  end
end

P4MessageOriginMigrationDrill.new.run(ARGV.fetch(0))
