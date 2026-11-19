# frozen_string_literal: true

module AiWorkspace
  module Errors
    class Unauthorized < StandardError; end
    class InvalidSelection < StandardError; end
    class InvalidPreset < StandardError; end
    class ConsentRequired < StandardError; end
    class BudgetExceeded < StandardError; end
    class ProviderUnavailable < StandardError; end
  end
end
