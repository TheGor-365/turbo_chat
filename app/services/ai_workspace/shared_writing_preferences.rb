# frozen_string_literal: true

module AiWorkspace
  class SharedWritingPreferences
    class Conflict < StandardError; end

    def self.read(room:, actor:)
      Room.uncached do
        room.with_lock do
          authorize!(room, actor)
          snapshot(room, actor, AiRoomSharedWritingPreference.find_by(room_id: room.id))
        end
      end
    end

    def self.write(room:, actor:, attributes:, expected_revision:)
      Room.uncached do
        room.with_lock do
          authorize!(room, actor)
          raise Errors::Unauthorized unless room.owned_by?(actor)
          unless expected_revision.instance_of?(Integer) && expected_revision >= 0 &&
              attributes.instance_of?(Hash) && attributes.keys.to_set == WritingPreferenceLayers::FIELDS.to_set
            raise Errors::InvalidPreset, "Invalid shared preference request."
          end
          WritingPreferenceLayers.resolve(shared: attributes)
          record = AiRoomSharedWritingPreference.find_or_initialize_by(room_id: room.id)
          raise Conflict unless record.revision == expected_revision

          record.assign_attributes(attributes)
          record.editor = actor
          # Identical writes are idempotent and retain their revision.
          record.save!
          snapshot(room, actor, record)
        end
      end
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
      raise Conflict
    end

    def self.authorize!(room, actor)
      unless actor&.persisted? && room.private_group? && room.accessible_to?(actor)
        raise Errors::Unauthorized
      end
    end
    private_class_method :authorize!

    def self.snapshot(room, actor, record)
      { configured: record.present?, preference: record&.public_snapshot,
        revision: record&.revision || 0, editable: room.owned_by?(actor),
        editor: record&.editor && { id: record.editor.id, label: record.editor.chat_label } }
    end
    private_class_method :snapshot
  end
end
