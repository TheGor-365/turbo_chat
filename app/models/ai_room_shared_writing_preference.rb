# frozen_string_literal: true

# Persistence only. Callers must enforce current owner/member ACL under the
# room lock. This record never grants history access or enables another's AI.
class AiRoomSharedWritingPreference < ApplicationRecord
  belongs_to :room
  belongs_to :editor, class_name: "User", optional: true

  validates :room_id, uniqueness: true
  validates :profile_id, inclusion: { in: AiRoomWritingPreference::PROFILE_IDS }, allow_nil: true
  validates :writing_style, inclusion: { in: AiRoomWritingPreference::STYLE_IDS }
  validates :language, inclusion: { in: AiRoomWritingPreference::LANGUAGES }
  validates :tone, inclusion: { in: AiRoomWritingPreference::TONES }
  validate :private_group_only
  validate :profile_matches_style

  def public_snapshot
    { profile_id: profile_id, writing_style: writing_style,
      language: language, tone: tone }
  end

  # First persisted snapshot has API revision 1; absence has revision 0.
  def revision
    persisted? ? lock_version + 1 : 0
  end

  private

  def private_group_only
    errors.add(:room, :invalid) unless room&.private_group?
  end

  def profile_matches_style
    return unless AiRoomWritingPreference::PROFILE_IDS.include?(profile_id)

    expected = AiWorkspace::ConversationExperienceV1.resolve(
      profile_id: profile_id
    ).settings.fetch(:writing_style)
    errors.add(:writing_style, :invalid) unless writing_style == expected
  end
end
