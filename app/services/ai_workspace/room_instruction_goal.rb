# frozen_string_literal: true

module AiWorkspace
  # Compatibility adapter for the S3 plan; the ONE editable room purpose is
  # the existing RoomAiInstructionRevision. No new mutable goal is created.
  # Legacy personal goals remain stored privately for non-destructive rollout.
  class RoomInstructionGoal
    Snapshot = Struct.new(:purpose, :revision, :sha256, keyword_init: true) do
      def public_snapshot
        { purpose: purpose, constraints: nil, desired_outcome: nil,
          revision: revision, active: true, source: "room_instructions",
          sha256: sha256 }
      end
    end

    def self.load!(room:, actor:, expected_revision: nil)
      saved = RoomInstructionContextV1.load!(room: room, actor: actor)
      if expected_revision && saved.revision_number != expected_revision
        raise Errors::InvalidSelection, "Room instruction revision changed."
      end
      Snapshot.new(purpose: saved.text, revision: saved.revision_number,
        sha256: saved.sha256).freeze
    end
  end
end
