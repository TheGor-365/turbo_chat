# frozen_string_literal: true

module AiWorkspace
  # Versioned, immutable, code-owned configuration. No arbitrary prompt text,
  # runtime YAML loading or user-editable instructions are accepted at this gate.
  class PresetDefinition
    SCHEMA_VERSION = 1
    KEYS = %w[schema_version id version operation label locale intent audience tone style constraints context output].freeze
    OPERATIONS = %w[beautify summarize translate suggest_reply].freeze
    LOCALES = %w[en ru hy].freeze
    INTENTS = %w[improve_clarity clarify_next_step explain summarize translate].freeze
    AUDIENCES = %w[client teammate general].freeze
    TONES = %w[professional friendly neutral technical].freeze
    STYLES = %w[concise balanced detailed].freeze
    CONSTRAINT_KEYS = %w[preserve_facts do_not_invent_prices do_not_invent_deadlines require_user_approval].freeze

    attr_reader :id, :version, :operation, :label, :locale, :snapshot

    def initialize(config)
      validate_hash!(config, KEYS)
      exact_integer!(config.fetch("schema_version"), SCHEMA_VERSION)
      exact_integer!(config.fetch("version"), 1)
      string_match!(config.fetch("id"), /\A[a-z][a-z0-9_]{2,49}\z/)
      label = config.fetch("label")
      string_match!(label, /\A[^\p{Cc}<>]{1,80}\z/)
      enum!(config.fetch("operation"), OPERATIONS)
      enum!(config.fetch("locale"), LOCALES)
      enum!(config.fetch("intent"), INTENTS)
      enum!(config.fetch("audience"), AUDIENCES)
      enum!(config.fetch("tone"), TONES)
      enum!(config.fetch("style"), STYLES)

      constraints = config.fetch("constraints")
      validate_hash!(constraints, CONSTRAINT_KEYS)
      CONSTRAINT_KEYS.each { |key| raise Errors::InvalidPreset, "Invalid preset." unless constraints[key] == true }

      context = config.fetch("context")
      validate_hash!(context, %w[policy max_messages])
      raise Errors::InvalidPreset, "Invalid preset." unless context["policy"] == "manual"
      max_messages = context.fetch("max_messages")
      raise Errors::InvalidPreset, "Invalid preset." unless max_messages.instance_of?(Integer) && max_messages.between?(1, 8)

      output = config.fetch("output")
      validate_hash!(output, %w[format variants])
      raise Errors::InvalidPreset, "Invalid preset." unless output["format"] == "plain_text" && output["variants"].instance_of?(Integer) && output["variants"] == 1

      # Rebuild from known scalar fields. Caller mutations cannot change a
      # selected version or relax constraints after validation.
      @snapshot = {
        "schema_version" => SCHEMA_VERSION,
        "id" => config.fetch("id").dup.freeze,
        "version" => 1,
        "operation" => config.fetch("operation").dup.freeze,
        "label" => label.dup.freeze,
        "locale" => config.fetch("locale").dup.freeze,
        "intent" => config.fetch("intent").dup.freeze,
        "audience" => config.fetch("audience").dup.freeze,
        "tone" => config.fetch("tone").dup.freeze,
        "style" => config.fetch("style").dup.freeze,
        "constraints" => CONSTRAINT_KEYS.to_h { |key| [key.freeze, true] }.freeze,
        "context" => { "policy" => "manual".freeze, "max_messages" => max_messages }.freeze,
        "output" => { "format" => "plain_text".freeze, "variants" => 1 }.freeze
      }.freeze
      @id = @snapshot.fetch("id")
      @version = @snapshot.fetch("version")
      @operation = @snapshot.fetch("operation")
      @label = @snapshot.fetch("label")
      @locale = @snapshot.fetch("locale")
      freeze
    rescue KeyError, TypeError
      raise Errors::InvalidPreset, "Invalid preset."
    end

    private

    def validate_hash!(hash, keys)
      unless hash.instance_of?(Hash) && hash.keys.all? { |key| key.instance_of?(String) } && hash.keys.sort == keys.sort
        raise Errors::InvalidPreset, "Invalid preset."
      end
    end

    def exact_integer!(value, expected)
      raise Errors::InvalidPreset, "Unsupported preset version." unless value.instance_of?(Integer) && value == expected
    end

    def string_match!(value, regex)
      raise Errors::InvalidPreset, "Invalid preset." unless value.instance_of?(String) && value.valid_encoding? && value.match?(regex)
    end

    def enum!(value, list)
      raise Errors::InvalidPreset, "Invalid preset." unless value.instance_of?(String) && list.include?(value)
    end
  end
end
