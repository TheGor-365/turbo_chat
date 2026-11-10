# frozen_string_literal: true

require "json"
require "net/http"

module AiWorkspace
  module Providers
    # H3b: isolated, testable xAI Responses transport. This is NOT called by
    # Gateway or any HTTP controller until a separate consent/budget gate exists.
    # Do not turn this into a general endpoint or accept a caller-supplied URL.
    class XaiResponses
      ENDPOINT = URI("https://api.x.ai/v1/responses")
      MODEL = "grok-4.3"
      OUTPUT_TOKENS = 800
      MAX_RESPONSE_BYTES = 64_000
      SystemInstruction = DraftPromptV1::POLISH
      Result = Struct.new(:text, :model, :input_tokens, :output_tokens,
        :cost_in_usd_ticks, keyword_init: true)

      class ProviderUnavailable < StandardError; end

      def initialize(api_key:, transport: nil)
        raise ProviderUnavailable, "Provider unavailable." unless api_key.is_a?(String) &&
          api_key.start_with?("xai-") && api_key.bytesize.between?(12, 512)

        @api_key = api_key
        @transport = transport
      end

      def generate!(prepared)
        draft, prompt = validate_prepared!(prepared)
        request = Net::HTTP::Post.new(ENDPOINT.request_uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(
          model: MODEL,
          input: [
            { role: "system", content: prompt },
            { role: "user", content: draft }
          ],
          store: false, tools: [], max_output_tokens: OUTPUT_TOKENS,
          reasoning: { effort: "none" }
        )

        response = @transport ? @transport.call(request) : send_request(request)
        raise ProviderUnavailable, "Provider unavailable." unless response.code.to_s == "200"
        body = response.body
        raise ProviderUnavailable, "Provider unavailable." unless body.is_a?(String) &&
          body.bytesize.between?(1, MAX_RESPONSE_BYTES)
        parse_response(JSON.parse(body))
      rescue JSON::ParserError, Timeout::Error, IOError, SystemCallError, SocketError,
        OpenSSL::SSL::SSLError
        raise ProviderUnavailable, "Provider unavailable."
      end

      private

      def validate_prepared!(prepared)
        unless prepared.is_a?(AiWorkspace::ContentPipeline::Prepared) &&
            prepared.source == "own_draft" &&
            prepared.rows.size == 1 && prepared.rows.first.source_id.nil?
          raise ProviderUnavailable, "Provider unavailable."
        end

        selected_id = prepared.preset_snapshot["id"]
        preset = AiWorkspace::PresetRegistry.bundled.fetch(selected_id)
        unless preset.operation == prepared.operation && preset.snapshot == prepared.preset_snapshot
          raise ProviderUnavailable, "Provider unavailable."
        end

        validated = AiWorkspace::Preprocessors::Text.call(prepared.rows.first.text)
        # Potential private addresses/tokens must be reviewed before any future
        # outbound invocation; not a guarantee of perfect DLP coverage.
        raise ProviderUnavailable, "Provider unavailable." unless validated.warnings.empty?
        prompt = DraftPromptV1.for(preset: preset, target_locale: prepared.target_locale)
        [validated.text, prompt]
      rescue AiWorkspace::Errors::InvalidPreset, AiWorkspace::Errors::InvalidSelection
        raise ProviderUnavailable, "Provider unavailable."
      end

      def send_request(request)
        Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true,
          open_timeout: 5, read_timeout: 30, write_timeout: 5) do |connection|
          connection.request(request)
        end
      end

      def parse_response(data)
        raise ProviderUnavailable, "Provider unavailable." unless data.is_a?(Hash) &&
          data["status"] == "completed" && data["model"] == MODEL
        messages = data["output"]
        raise ProviderUnavailable, "Provider unavailable." unless messages.is_a?(Array)
        text_segments = messages.filter_map do |item|
          next unless item.is_a?(Hash) && item["type"] == "message" && item["role"] == "assistant"
          next unless item["content"].is_a?(Array)
          item["content"].filter_map do |segment|
            segment["text"] if segment.is_a?(Hash) && segment["type"] == "output_text"
          end
        end.flatten
        raise ProviderUnavailable, "Provider unavailable." unless text_segments.size == 1
        result = AiWorkspace::Preprocessors::Text.call(text_segments.first)
        usage = data["usage"]
        raise ProviderUnavailable, "Provider unavailable." unless usage.is_a?(Hash)
        input_tokens = usage["input_tokens"]
        output_tokens = usage["output_tokens"]
        cost_ticks = usage["cost_in_usd_ticks"]
        unless [input_tokens, output_tokens, cost_ticks].all? { |v| v.is_a?(Integer) && v >= 0 }
          raise ProviderUnavailable, "Provider unavailable."
        end

        Result.new(text: result.text, model: MODEL, input_tokens: input_tokens,
          output_tokens: output_tokens, cost_in_usd_ticks: cost_ticks).freeze
      rescue AiWorkspace::Errors::InvalidSelection
        raise ProviderUnavailable, "Provider unavailable."
      end
    end
  end
end
