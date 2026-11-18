# frozen_string_literal: true

module AiWorkspace
  # FCC-2b: explicit read-only, metadata-only preview of the entire eligible
  # room history (up to the bounded FCC-2a maximum). This is NOT a source
  # selection token, provider consent or permission to generate a paid reply.
  class ConversationCoveragePreviewV1
    VERSION = 1
    DEFAULT_PAGE_SIZE = 25
    MAX_PAGE_SIZE = 50
    MAX_TOKEN_BYTES = 4_096
    TOKEN_TTL = 5.minutes

    def initialize(snapshot: ConversationCoverageSnapshotV2.new)
      @snapshot = snapshot
    end

    def call(room:, actor:, page: nil, page_size: nil, token: nil)
      page_number = parse_number(page, default: 1, maximum: 10_000)
      size = parse_number(page_size, default: DEFAULT_PAGE_SIZE, maximum: MAX_PAGE_SIZE)
      report = @snapshot.build(room: room, actor: actor)
      source_count = report.included_text_messages
      pages = [(source_count.to_f / size).ceil, 1].max

      unless page_number <= pages
        raise Errors::InvalidSelection, "Coverage page is unavailable."
      end

      receipt = {
        "version" => VERSION, "room_id" => room.id, "actor_id" => actor.id,
        "snapshot_version" => report.version, "source_sha256" => report.source_sha256,
        "consent_sha256" => report.consent_sha256, "size" => size,
        "total_messages" => report.total_messages,
        "eligible_sources" => source_count
      }
      # Every page beyond the first must prove it belongs to the same source
      # snapshot, room, account, grant state and page size. Expired receipts
      # require restarting at page one; never continue on modified history.
      if page_number > 1 || token.present?
        unless token.is_a?(String) && token.bytesize.between?(1, MAX_TOKEN_BYTES) &&
            signer.verified(token) == receipt
          raise Errors::InvalidSelection, "Coverage preview expired or changed."
        end
      end

      start = (page_number - 1) * size
      selected = report.sources.slice(start, size) || []
      excluded = {
        former_author: report.excluded_departed_author,
        non_text: report.excluded_non_text,
        sensitive: report.excluded_sensitive,
        invalid: report.excluded_invalid
      }.freeze
      excluded_total = excluded.values.sum
      unless report.current_author_messages + report.excluded_departed_author == report.total_messages &&
          source_count + excluded_total == report.total_messages
        raise Errors::InvalidSelection, "Coverage counts are inconsistent."
      end

      {
        version: VERSION,
        snapshot_version: report.version,
        state: "metadata_only_not_sent_to_ai",
        scope: "consented_private_room",
        coverage: {
          total_messages: report.total_messages,
          current_author_messages: report.current_author_messages,
          eligible_safe_text: source_count,
          excluded_messages: excluded_total,
          exclusions: excluded
        },
        pagination: {
          page: page_number, page_size: size, total_pages: pages,
          total_eligible_sources: source_count,
          has_more: page_number < pages
        },
        # These IDs are read-only locators, never provider input or proof of
        # consent. Deliberately omit text, body hashes and author identities.
        sources: selected.map { |source|
          { id: source.message_id, updated_at: source.updated_at }
        },
        next_page_token: page_number < pages ? (token.presence || signer.generate(
          receipt, expires_in: TOKEN_TTL
        )) : nil
      }.freeze
    rescue ActiveSupport::MessageVerifier::InvalidSignature, TypeError, ArgumentError
      raise Errors::InvalidSelection, "Invalid or expired coverage preview."
    end

    private

    def parse_number(value, default:, maximum:)
      return default if value.nil?
      unless value.instance_of?(String) && value.match?(/\A[1-9][0-9]{0,4}\z/)
        raise Errors::InvalidSelection, "Invalid coverage page."
      end
      number = value.to_i
      unless number.between?(1, maximum)
        raise Errors::InvalidSelection, "Invalid coverage page."
      end

      number
    end

    def signer
      Rails.application.message_verifier("ai-workspace/coverage-preview/v1")
    end
  end
end
