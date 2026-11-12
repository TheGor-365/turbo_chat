# frozen_string_literal: true

# CI-ONLY staged media writer. Two independent production-mode processes pause
# with committed message rows but without their attachments. This makes an
# actual DB/media consistency window observable before backup quiescence.
# NOT an application-wide production write lock or a Railway backup mechanism.
require "stringio"

id = ENV.fetch("RELAY_CI_WRITER_ID")
root = ENV.fetch("TURBO_CHAT_STORAGE_ROOT")
pg_host = ENV.fetch("PGHOST")
room_id = Integer(ENV.fetch("RELAY_CI_ROOM_ID"))
expected_mount = "/data/turbo-chat-private"
abort "Refusing non-synthetic CI writer" unless
  Rails.env.production? &&
  ENV["RELAY_CI_SYNTHETIC_WRITER"] == "1" &&
  %w[1 2].include?(id) &&
  pg_host.start_with?("relay-smoke-") && pg_host.end_with?("-postgres") &&
  root == expected_mount &&
  ENV["RAILWAY_VOLUME_NAME"] == "ci-only-private-volume"

marker = File.join(root, ".ci-writer-active-#{id}")
release = File.join(root, ".ci-writer-release")
abort "Unexpected existing writer marker" if File.exist?(marker)

room = Room.find(room_id)
abort "CI fixture is not a private room" unless room.is_private?
member = User.find_by!(email: "relay-ci-member@example.test")
abort "CI writer does not belong to the room" unless room.accessible_to?(member)

# Message row becomes visible to other transactions before the file appears.
message = room.messages.create!(user: member, body: "relay-ci-concurrent-write:#{id}")
begin
  File.write(marker, "in-flight\n")
  # The orchestrator must prove snapshot refusal during this real write gap.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
  until File.exist?(release)
    abort "CI writer release barrier timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.1
  end

  payload = "relay-ci-concurrent-media:#{id}\n"
  message.attachments.attach(
    io: StringIO.new(payload),
    filename: "relay-ci-writer-#{id}.txt",
    content_type: "text/plain"
  )
  abort "CI staged media did not persist" unless
    message.reload.attachments.size == 1 &&
    message.attachments.first.blob.download == payload
  puts "CI synthetic writer #{id} committed message and matching media"
ensure
  File.delete(marker) if File.file?(marker)
end
