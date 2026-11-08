# frozen_string_literal: true

module AiWorkspace
  # This gate can inspect only an explicit member's own draft or the existing
  # Scope's individual message selection. Smart/agent context is always OFF.
  class ContextPolicy
    def initialize(mode: "manual")
      @mode = mode
    end

    def authorize_actor!(room:, actor:)
      raise Errors::ConsentRequired, "Context mode is unavailable." unless @mode == "manual"
      raise Errors::Unauthorized, "Conversation unavailable." unless room&.accessible_to?(actor)
      true
    end

    def review(room:, actor:, operation:, source_ids:)
      authorize_actor!(room: room, actor: actor)
      AiWorkspace::Scope.new(
        room: room, actor: actor, operation: operation, message_ids: source_ids
      ).review
    rescue AiWorkspace::Scope::Unauthorized
      raise Errors::Unauthorized, "Conversation unavailable."
    rescue AiWorkspace::Scope::InvalidSelection
      raise Errors::InvalidSelection, "Invalid selection."
    end
  end
end
