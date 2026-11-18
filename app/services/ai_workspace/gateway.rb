# frozen_string_literal: true

module AiWorkspace
  # Fail-closed provider boundary. A future provider integration must replace
  # this only AFTER approved retention/privacy terms, durable room consent,
  # per-user quotas and explicit financial limits are implemented and tested.
  # There is intentionally no transport or environment-token lookup today.
  class Gateway
    class ProviderUnavailable < StandardError; end

    def self.configured?
      false
    end

    def self.generate!(*)
      raise ProviderUnavailable, "No AI provider is configured."
    end
  end
end
