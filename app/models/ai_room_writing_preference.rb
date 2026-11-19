# frozen_string_literal: true

# Personal settings inside a room; never shared member consent or access rights.
# These values only select an existing *manual* AI writing preset, and never
# enable provider spending or room-history ingestion.
class AiRoomWritingPreference < ApplicationRecord
  belongs_to :room
  belongs_to :user

  PROFILE_IDS = AiWorkspace::ConversationExperienceV1::PROFILES.keys.freeze
  STYLE_IDS = AiWorkspace::ConversationExperienceV1::FIELD_VALUES.fetch(:writing_style)
  LANGUAGES = AiWorkspace::ConversationExperienceV1::FIELD_VALUES.fetch(:language)
  TONES = AiWorkspace::ConversationExperienceV1::FIELD_VALUES.fetch(:tone)

  validates :profile_id, inclusion: { in: PROFILE_IDS }, allow_nil: true
  validates :writing_style, inclusion: { in: STYLE_IDS }
  validates :language, inclusion: { in: LANGUAGES }
  validates :tone, inclusion: { in: TONES }
  validates :user_id, uniqueness: { scope: :room_id }
  validate :selected_profile_matches_style

  def public_snapshot
    { profile_id: profile_id, writing_style: writing_style,
      language: language, tone: tone }
  end

  def experience
    AiWorkspace::ConversationExperienceV1.resolve(
      profile_id: profile_id || "universal",
      room: { writing_style: writing_style, language: language, tone: tone }
    )
  end

  private

  def selected_profile_matches_style
    return if profile_id.blank? || !PROFILE_IDS.include?(profile_id)
    expected = AiWorkspace::ConversationExperienceV1.resolve(
      profile_id: profile_id
    ).settings.fetch(:writing_style)
    errors.add(:writing_style, :invalid) unless writing_style == expected
  end
end
