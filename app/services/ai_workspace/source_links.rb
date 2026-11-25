# frozen_string_literal: true

module AiWorkspace
  # Source URLs are generated from records in the current room, never from
  # model-authored [M...] tokens. Room#show rechecks membership and focus
  # ownership for every subsequent GET, including after removal or leave.
  class SourceLinks
    MAX_SOURCES = 9

    def self.for_authorized_room!(room:, actor:, ids:)
      ActiveRecord::Base.uncached do
        permitted = RoomContextAccess.new.authorize_independent!(room: room.reload, actor: actor)
        links = for_room!(room: room, ids: ids)
        unless room.messages.where(id: ids, user_id: permitted.allowed_author_ids).count == ids.size
          raise Errors::ConsentRequired, "Source access changed."
        end
        links
      end
    end

    def self.for_room!(room:, ids:)
      unless ids.is_a?(Array) && ids.any? && ids.size <= MAX_SOURCES &&
          ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
          ids.uniq.size == ids.size
        raise Errors::InvalidSelection, "Invalid source references."
      end

      found = room.messages.where(id: ids).pluck(:id)
      unless found.size == ids.size && found.sort == ids.sort
        raise Errors::InvalidSelection, "Source not found in this room."
      end

      ids.index_with do |id|
        Rails.application.routes.url_helpers.room_path(room, focus: id)
      end
    end
  end
end
