# frozen_string_literal: true

module AiWorkspace
  # Foundation for the owner-approved per-author AI context policy.
  #
  # This is a read-only capability snapshot, NOT an authorization shortcut.
  # It does not alter the existing unanimous-consent provider path. Before
  # callers may use this result, source retrieval, signed receipts, pre/post
  # provider checks, previews and Send must ALL revalidate author grants.
  class ContextAuthorPolicy
    Selection = Struct.new(:allowed_author_ids, :withheld_author_ids,
      :actor_history_granted, :member_count, keyword_init: true)

    def resolve(room:, actor:)
      raise Errors::Unauthorized, "Conversation unavailable." unless
        actor&.persisted? && room&.accessible_to?(actor)
      raise Errors::ConsentRequired, "Private room required." unless room.is_private?
      raise Errors::ConsentRequired, "Author grants unavailable." unless
        RoomContextAccess.available?

      members = room.participants.distinct.pluck(:user_id).sort
      raise Errors::Unauthorized, "Conversation unavailable." unless members.include?(actor.id)
      raise Errors::ConsentRequired, "Room membership is not eligible." unless
        members.size.between?(1, RoomContextAccess::MAX_PARTICIPANTS)

      # Only current authors who explicitly granted use of their historical
      # messages are included. Room ownership and other members' grants never
      # imply permission to transmit a withheld author's content.
      granted = AiRoomContextConsent.where(room_id: room.id, user_id: members,
        revoked_at: nil).where.not(granted_at: nil).pluck(:user_id).uniq.sort

      Selection.new(allowed_author_ids: granted.freeze,
        withheld_author_ids: (members - granted).freeze,
        actor_history_granted: granted.include?(actor.id),
        member_count: members.size).freeze
    end
  end
end
