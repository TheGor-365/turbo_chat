# frozen_string_literal: true

module AiWorkspace
  # Writing preferences only, never AI enablement or author-history grants.
  # Existing personal room rows remain complete overrides. Shared defaults
  # apply only to current private-group members without a personal row.
  class WritingPreferenceResolver
    Result = Struct.new(:effective, :source, :room_configured,
      :account_configured, :experience, :origins, :shared_configured,
      :shared_revision, keyword_init: true)

    def self.for(user:, room:)
      raise Errors::Unauthorized, "Unauthorized preferences" unless
        user&.persisted? && room&.persisted?

      Room.uncached do
        room = Room.find_by(id: room.id)
        raise Errors::Unauthorized, "Unauthorized preferences" unless room&.accessible_to?(user)

        account = AiAccountWritingPreference.find_by(user_id: user.id)
        local = AiRoomWritingPreference.find_by(user_id: user.id, room_id: room.id)
        shared = AiRoomSharedWritingPreference.find_by(room_id: room.id) if room.private_group?
        layers = WritingPreferenceLayers.resolve(account: account&.public_snapshot,
          shared: shared&.public_snapshot, personal: local&.public_snapshot)
        profile = layers.effective.fetch(:profile_id) || "universal"
        override = layers.effective.slice(:writing_style, :language, :tone)
        experience = ConversationExperienceV1.resolve(
          profile_id: profile,
          account: (layers.source == "account" ? override : {}),
          room: (%w[room shared].include?(layers.source) ? override : {})
        )
        raise Errors::Unauthorized, "Unauthorized preferences" unless room.reload.accessible_to?(user)
        Result.new(effective: layers.effective, source: layers.source,
          room_configured: local.present?, account_configured: account.present?,
          experience: experience, origins: layers.origins,
          shared_configured: shared.present?, shared_revision: shared&.revision || 0).freeze
      end
    end
  end
end
