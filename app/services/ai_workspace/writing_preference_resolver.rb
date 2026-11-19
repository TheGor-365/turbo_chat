# frozen_string_literal: true

module AiWorkspace
  # Effective write-only preferences, not permissions. Existing room rows
  # win in full over an account row. Missing room rows inherit account
  # defaults; otherwise use system defaults. A separate explicit deletion
  # returns an existing room to account-level inheritance.
  class WritingPreferenceResolver
    Result = Struct.new(:effective, :source, :room_configured,
      :account_configured, :experience, keyword_init: true)

    def self.for(user:, room:)
      raise Errors::Unauthorized, "Unauthorized preferences" unless
        user&.persisted? && room&.accessible_to?(user)

      account = AiAccountWritingPreference.find_by(user_id: user.id)
      local = AiRoomWritingPreference.find_by(user_id: user.id, room_id: room.id)
      source = local ? "room" : account ? "account" : "system"
      snapshot = if local
        local.public_snapshot
      elsif account
        account.public_snapshot
      else
        { profile_id: "universal", writing_style: "polish_clarity",
          language: "auto", tone: "neutral" }
      end
      profile = snapshot.fetch(:profile_id) || "universal"
      override = snapshot.slice(:writing_style, :language, :tone)
      experience = ConversationExperienceV1.resolve(
        profile_id: profile,
        account: (source == "account" ? override : {}),
        room: (source == "room" ? override : {})
      )
      Result.new(effective: snapshot.freeze, source: source.freeze,
        room_configured: local.present?, account_configured: account.present?,
        experience: experience).freeze
    end
  end
end
