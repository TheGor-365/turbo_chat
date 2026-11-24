# frozen_string_literal: true

module AiWorkspace
  class PersonalEnablement
    class Conflict < StandardError; end

    # Missing state preserves legacy *manual* tool availability; existing
    # provider, grant, confirmation and budget gates remain mandatory.
    Snapshot = Struct.new(:enabled, :configured, :revision, keyword_init: true)

    def self.read(actor:)
      authorize_actor!(actor)
      ActiveRecord::Base.uncached do
        snapshot(AiPersonalEnablement.find_by(user_id: actor.id))
      end
    end

    def self.write(actor:, enabled:, expected_revision:)
      authorize_actor!(actor)
      unless [true, false].include?(enabled) && expected_revision.instance_of?(Integer) && expected_revision >= 0
        raise Errors::InvalidSelection, "Invalid personal AI setting."
      end

      ActiveRecord::Base.uncached do
        User.find(actor.id).with_lock do
          item = AiPersonalEnablement.find_by(user_id: actor.id)
          raise Conflict unless snapshot(item).revision == expected_revision
          item ||= AiPersonalEnablement.new(user_id: actor.id)
          item.enabled = enabled
          item.save!
          snapshot(item)
        end
      end
    end

    def self.snapshot(item)
      Snapshot.new(enabled: item ? item.enabled : true,
        configured: item.present?, revision: item ? item.revision : 0).freeze
    end
    private_class_method :snapshot

    def self.authorize_actor!(actor)
      unless actor.is_a?(User) && actor.persisted? && User.exists?(actor.id)
        raise Errors::Unauthorized, "Account unavailable."
      end
    end
    private_class_method :authorize_actor!
  end
end
