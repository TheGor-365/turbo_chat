# frozen_string_literal: true

module AiWorkspace
  # Separate consent boundary for future asynchronous processing. Always
  # requires existing unanimous MANUAL-context consent plus fresh explicit
  # background consent from EVERY CURRENT participant. The actor alone must
  # additionally opt in to unattended Send or scheduled document creation.
  #
  # A PASS is only a consent check. It DOES NOT authorize provider spend,
  # queue execution, room Send, or any automatic message.
  class AutomationConsentGate
    MODES = %w[review unattended outcome].freeze
    Result = Struct.new(:consent_ready, :execution_authorized,
      :members, :mode, keyword_init: true)

    def initialize(manual_access: RoomContextAccess.new)
      @manual_access = manual_access
    end

    def check!(room:, actor:, mode:)
      raise Errors::ConsentRequired, "Unsupported background processing mode" unless
        MODES.include?(mode)
      @manual_access.authorize!(room: room, actor: actor)
      members = room.participants.distinct.pluck(:user_id)
      fingerprint = AiRoomAutomationConsent.fingerprint_for(room)

      current = AiRoomAutomationConsent.where(room_id: room.id, user_id: members,
        member_set_fingerprint: fingerprint, background_context_enabled: true).to_a
      unless current.size == members.size && current.map(&:user_id).sort == members.sort
        raise Errors::ConsentRequired, "All participants must explicitly allow background processing"
      end

      own = current.find { |entry| entry.user_id == actor.id }
      additional = case mode
      when "unattended" then own&.unattended_send_enabled?
      when "outcome" then own&.scheduled_outcomes_enabled?
      else true
      end
      raise Errors::ConsentRequired, "This user has not authorized that operation" unless additional

      # Membership and existing manual grants can change while querying.
      @manual_access.authorize!(room: room.reload, actor: actor)
      raise Errors::ConsentRequired, "Room membership changed" unless
        AiRoomAutomationConsent.fingerprint_for(room) == fingerprint

      Result.new(consent_ready: true, execution_authorized: false,
        mode: mode, members: members.length).freeze
    end
  end
end
