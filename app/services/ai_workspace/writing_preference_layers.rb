# frozen_string_literal: true

module AiWorkspace
  # Pure contract for the initial full-snapshot compatibility rollout.
  # No database, provider, history permission or message-send side effects.
  class WritingPreferenceLayers
    FIELDS = %i[profile_id writing_style language tone].freeze
    DEFAULTS = { profile_id: "universal", writing_style: "polish_clarity",
      language: "auto", tone: "neutral" }.freeze
    Result = Struct.new(:effective, :source, :origins, keyword_init: true)

    def self.resolve(account: nil, shared: nil, personal: nil)
      layers = { "account" => account, "shared" => shared, "room" => personal }
      layers.each_value { |snapshot| validate!(snapshot) unless snapshot.nil? }
      source, snapshot = layers.to_a.reverse.find { |_, value| !value.nil? } ||
        ["system", DEFAULTS]
      effective = snapshot.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
      Result.new(effective: effective, source: source.freeze,
        origins: FIELDS.to_h { |field| [field, source] }.freeze).freeze
    end

    def self.validate!(snapshot)
      unless snapshot.is_a?(Hash) && snapshot.keys.sort_by(&:to_s) == FIELDS.sort_by(&:to_s)
        raise Errors::InvalidPreset, "Expected a complete writing preference snapshot."
      end
      profile = snapshot.fetch(:profile_id)
      unless profile.nil? || ConversationExperienceV1::PROFILES.key?(profile)
        raise Errors::InvalidPreset, "Invalid writing profile."
      end
      %i[writing_style language tone].each do |field|
        unless ConversationExperienceV1::FIELD_VALUES.fetch(field).include?(snapshot.fetch(field))
          raise Errors::InvalidPreset, "Invalid writing preference."
        end
      end
      if profile && ConversationExperienceV1.resolve(profile_id: profile).settings.fetch(:writing_style) != snapshot[:writing_style]
        raise Errors::InvalidPreset, "Writing profile and style do not match."
      end
    end
    private_class_method :validate!
  end
end
