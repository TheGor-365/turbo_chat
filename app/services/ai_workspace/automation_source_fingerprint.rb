# frozen_string_literal: true

require "digest"
require "json"

module AiWorkspace
  # Shared snapshot-hash contract for metadata capture and safety rechecks.
  # Stable across processes, with no persistence of raw source text.
  module AutomationSourceFingerprint
    VERSION = 1

    def self.incoming(message)
      Digest::SHA256.hexdigest(JSON.generate([
        VERSION, "incoming", message.id, message.updated_at.iso8601(6), message.body
      ]))
    end

    def self.outcome(bundle)
      Digest::SHA256.hexdigest(JSON.generate([
        VERSION, "outcome",
        *bundle.rows.map do |row|
          [row.message_id, row.speaker, row.text, row.truncated]
        end
      ]))
    end
  end
end
