# frozen_string_literal: true

module AiWorkspace
  # Product-level preference contract; intentionally NOT connected to the
  # provider, Send, room-history reads, localStorage or persistence yet.
  # Profile and overrides are selected by an authenticated caller in later gates.
  #
  # Precedence: system < reusable profile < account < room < dialogue < message.
  # Hard safety boundaries are never options in any override layer.
  class ConversationExperienceV1
    VERSION = 1

    FIELD_VALUES = {
      tone: %w[neutral professional warm technical],
      language: %w[auto ru en hy es],
      writing_style: PresetRegistry::EXPECTED_IDS,
      incoming_translation: %w[on_if_supported off],
      beautify: %w[on_request off],
      contextual_help: %w[on_with_consent off],
      document_kind: %w[none conversation_summary action_items client_brief client_proposal content_outline]
    }.transform_values { |values| values.dup.freeze }.freeze

    DEFAULTS = {
      tone: "neutral",
      language: "auto",
      writing_style: "polish_clarity",
      incoming_translation: "on_if_supported",
      beautify: "on_request",
      contextual_help: "on_with_consent",
      document_kind: "none"
    }.freeze

    PROFILES = {
      "universal" => {},
      "business" => {
        tone: "professional",
        writing_style: "professional_client_reply",
        document_kind: "client_brief"
      },
      "personal" => {tone: "warm", writing_style: "friendly"},
      "dating" => {tone: "warm", writing_style: "friendly"},
      "development" => {
        tone: "technical",
        writing_style: "technical_summary",
        document_kind: "action_items"
      }
    }.transform_values { |profile| profile.freeze }.freeze

    # A one-message change is ephemeral. It must not toggle room-wide
    # translation or consent-based history assistance.
    LAYERS = {
      account: FIELD_VALUES.keys.freeze,
      room: FIELD_VALUES.keys.freeze,
      dialogue: FIELD_VALUES.keys.freeze,
      message: %i[tone language writing_style beautify document_kind].freeze
    }.freeze

    RUNTIME_CAPABILITIES = %i[
      local_translation_available room_context_authorized provider_available
    ].freeze

    SAFETY = {
      provider_spend: "per_request_explicit",
      room_history: "unanimous_current_consent",
      chat_send: "human_controlled",
      auto_publish: false,
      auto_retry_paid: false
    }.freeze

    Result = Struct.new(:version, :profile_id, :settings, :origins,
      :availability, :safety, keyword_init: true)

    def self.resolve(profile_id: "universal", account: {}, room: {},
      dialogue: {}, message: {}, runtime: {})
      unless profile_id.instance_of?(String) && PROFILES.key?(profile_id)
        raise Errors::InvalidPreset, "Unknown chat configuration."
      end
      validate_runtime!(runtime)

      settings = DEFAULTS.dup
      origins = settings.keys.to_h { |key| [key, "system"] }
      PROFILES.fetch(profile_id).each do |key, value|
        settings[key] = value
        origins[key] = "profile"
      end

      {account: account, room: room, dialogue: dialogue, message: message}.each do |layer, values|
        validate_layer!(layer, values)
        values.each do |key, value|
          settings[key] = value
          origins[key] = layer.to_s
        end
      end

      availability = {
        incoming_translation: if settings[:incoming_translation] == "off"
          "off"
        elsif runtime[:local_translation_available]
          "on_device_available"
        else
          "show_original_until_supported"
        end,
        contextual_help: if settings[:contextual_help] == "off"
          "off"
        elsif runtime[:room_context_authorized]
          "consent_scoped"
        else
          "requires_current_consent"
        end,
        beautify: if settings[:beautify] == "off"
          "off"
        elsif runtime[:provider_available]
          "manual_request_only"
        else
          "unavailable"
        end
      }.freeze

      Result.new(version: VERSION, profile_id: profile_id,
        settings: settings.freeze, origins: origins.freeze,
        availability: availability, safety: SAFETY).freeze
    end

    def self.validate_layer!(layer, values)
      unless values.instance_of?(Hash) && values.keys.all? do |key|
        key.instance_of?(Symbol) && LAYERS.fetch(layer).include?(key)
      end
        raise Errors::InvalidPreset, "Invalid chat preference scope."
      end
      values.each do |key, value|
        unless value.instance_of?(String) && FIELD_VALUES.fetch(key).include?(value)
          raise Errors::InvalidPreset, "Unsupported chat preference."
        end
      end
    end
    private_class_method :validate_layer!

    def self.validate_runtime!(runtime)
      unless runtime.instance_of?(Hash) &&
          runtime.keys.all? { |key| key.instance_of?(Symbol) && RUNTIME_CAPABILITIES.include?(key) } &&
          runtime.values.all? { |value| value == true || value == false }
        raise Errors::InvalidPreset, "Invalid chat capabilities."
      end
    end
    private_class_method :validate_runtime!
  end
end
