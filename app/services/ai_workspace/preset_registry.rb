# frozen_string_literal: true

require "yaml"

module AiWorkspace
  # Immutable registry: only code-owned local presets are accepted; no YAML
  # objects, symbols, aliases, arbitrary prompts or user-provided files.
  class PresetRegistry
    BUNDLED_PATH = Rails.root.join("config/ai_workspace/presets.yml")
    EXPECTED_IDS = %w[
      polish_clarity professional_client_reply friendly concise
      translate_preserving_tone technical_summary
    ].freeze
    MAX_BYTES = 20_000

    def self.bundled
      @bundled ||= new
    end

    def initialize(path: BUNDLED_PATH)
      raw = File.binread(path)
      raise Errors::InvalidPreset, "Invalid preset library." unless raw.bytesize.between?(1, MAX_BYTES)
      data = YAML.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
      raise Errors::InvalidPreset, "Invalid preset library." unless data.instance_of?(Array) && data.size == EXPECTED_IDS.size

      definitions = data.map { |config| PresetDefinition.new(config) }
      ids = definitions.map(&:id)
      unless ids.uniq.size == ids.size && ids.sort == EXPECTED_IDS.sort
        raise Errors::InvalidPreset, "Invalid preset library."
      end

      @all = definitions.freeze
      @by_id = definitions.to_h { |preset| [preset.id, preset] }.freeze
      freeze
    rescue Psych::Exception, ArgumentError, EncodingError, Errno::ENOENT, Errno::EISDIR
      raise Errors::InvalidPreset, "Invalid preset library."
    end

    def all
      @all
    end

    def for_operation(operation)
      @all.select { |preset| preset.operation == operation }.freeze
    end

    def fetch(id)
      raise Errors::InvalidPreset, "Unknown preset." unless id.is_a?(String) && @by_id.key?(id)

      @by_id.fetch(id)
    end
  end
end
