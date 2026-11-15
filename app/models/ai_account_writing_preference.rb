# frozen_string_literal: true

# The owner's reusable writing defaults. Never grants AI access to room
# history, attachments, external provider spending or message sending.
class AiAccountWritingPreference < ApplicationRecord
  belongs_to :user

  PROFILE_IDS = AiRoomWritingPreference::PROFILE_IDS
  STYLE_IDS = AiRoomWritingPreference::STYLE_IDS
  LANGUAGES = AiRoomWritingPreference::LANGUAGES
  TONES = AiRoomWritingPreference::TONES

  validates :user_id, uniqueness: true
  validates :profile_id, inclusion: { in: PROFILE_IDS }, allow_nil: true
  validates :writing_style, inclusion: { in: STYLE_IDS }
  validates :language, inclusion: { in: LANGUAGES }
  validates :tone, inclusion: { in: TONES }
  validate :selected_profile_matches_style

  def public_snapshot
    { profile_id: profile_id, writing_style: writing_style,
      language: language, tone: tone }
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
