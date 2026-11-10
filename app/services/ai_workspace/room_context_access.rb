# frozen_string_literal: true

module AiWorkspace
  # One member's opt-in is not a grant from everyone else. Context is ready
  # only while every CURRENT private-room participant has given permission.
  # Public rooms, anonymous viewers and unjoined accounts are fail-closed.
  class RoomContextAccess
    MAX_PARTICIPANTS = 10
    Status = Struct.new(:enabled, :ready, :members, :granted, keyword_init: true)

    def self.available?
      AiRoomContextConsent.table_exists?
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      false
    end

    def status(room:, actor:)
      raise Errors::Unauthorized, "Conversation unavailable." unless room&.accessible_to?(actor)
      raise Errors::ConsentRequired, "Private room required." unless room.is_private?
      raise Errors::ConsentRequired, "Context grants unavailable." unless self.class.available?

      members = room.participants.distinct.pluck(:user_id)
      if members.size < 2 || members.size > MAX_PARTICIPANTS || !members.include?(actor.id)
        raise Errors::ConsentRequired, "Room membership is not eligible."
      end
      # Validate all member records are present, not just the requesting actor.
      granted_ids = AiRoomContextConsent.where(room_id: room.id, user_id: members,
        revoked_at: nil).where.not(granted_at: nil).pluck(:user_id).uniq
      Status.new(enabled: granted_ids.include?(actor.id),
        ready: (members - granted_ids).empty?,
        members: members.size, granted: granted_ids.size).freeze
    end

    def authorize!(room:, actor:)
      state = status(room: room, actor: actor)
      raise Errors::ConsentRequired, "Each participant must enable AI context." unless state.ready
      state
    end
  end
end
