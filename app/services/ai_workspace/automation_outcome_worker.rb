# frozen_string_literal: true

require "digest"
require "securerandom"

module AiWorkspace
  # S7-C first deterministic executor: a PostgreSQL outbox using row locks,
  # bounded retries and atomic document+queue commit. No provider/API call.
  # Enqueue is EXPLICIT, scheduler and event discovery are not yet connected.
  class AutomationOutcomeWorker
    LEASE_SECONDS = 90

    def initialize(preflight: AutomationRunPreflight.new,
      consent: AutomationConsentGate.new, builder: ReplyContextBuilder.new)
      @preflight = preflight
      @consent = consent
      @builder = builder
    end

    def enqueue!(run:)
      raise Errors::InvalidSelection, "Invalid automation task" unless
        run.is_a?(AiAutomationRun) && run.run_kind == "conversation_outcome" &&
        run.status == "recorded"

      verify!(run)
      AiAutomationWorkItem.find_or_create_by!(ai_automation_run: run) do |item|
        item.state = "queued"
      end
    end

    # Atomic claim across any number of worker processes. Expired leases can
    # be retried, but no paid side-effect exists in this first worker.
    def claim_next!
      AiAutomationWorkItem.transaction do
        item = AiAutomationWorkItem
          .where("state = ? OR (state = ? AND lease_until < ?)",
            "queued", "leased", Time.current)
          .where("attempts < ?", AiAutomationWorkItem::MAX_ATTEMPTS)
          .order(:id).lock("FOR UPDATE SKIP LOCKED").first
        return nil unless item

        token = SecureRandom.hex(32)
        item.update!(state: "leased", attempts: item.attempts + 1,
          lease_token: token, lease_until: Time.current + LEASE_SECONDS.seconds)
        { id: item.id, token: token }.freeze
      end
    end

    def process_one!
      claim = claim_next!
      return false unless claim

      begin
        complete!(id: claim.fetch(:id), token: claim.fetch(:token))
      rescue Errors::Unauthorized, Errors::ConsentRequired, Errors::InvalidSelection
        block_claim!(id: claim.fetch(:id), token: claim.fetch(:token))
      end
      true
    end

    private

    def verify!(run)
      @preflight.check!(run: run)
      @consent.check!(room: run.room, actor: run.user, mode: "outcome")
      unless AiAutomationPolicy::PREVIEW_KINDS.include?(run.ai_automation_policy.summary_kind)
        raise Errors::InvalidSelection, "Document kind not available for offline automation"
      end
    end

    def complete!(id:, token:)
      AiAutomationWorkItem.transaction do
        item = AiAutomationWorkItem.lock.find(id)
        validate_lease!(item, token)
        run = item.ai_automation_run
        room = run.room

        room.with_lock do
          verify!(run)
          bundle = @builder.build(room: room, actor: run.user, **run.outcome_source_options)
          # The snapshot preflight verifies source IDs and full snippet hash.
          result = case run.ai_automation_policy.summary_kind
          when "conversation_summary"
            AutomaticEvidenceDraftV1.build!(bundle: bundle)
          when "client_brief"
            AutomaticClientBriefV1.build!(bundle: bundle)
          else
            raise Errors::InvalidSelection, "Unsupported offline outcome"
          end
          StructuredDeliverableMarkdownV1.parse!(text: result.text,
            kind: result.kind, bundle: bundle)
          @consent.check!(room: room.reload, actor: run.user, mode: "outcome")
          @preflight.check!(run: run)

          document = AiDeliverable.create!(room: room, owner: run.user,
            kind: result.kind, state: "draft")
          document.revisions.create!(author: run.user, version: 1,
            body_markdown: result.text,
            body_sha256: Digest::SHA256.hexdigest(result.text),
            source_message_ids: result.source_ids)
          item.update!(state: "completed", lease_token: nil, lease_until: nil,
            ai_deliverable: document, completed_at: Time.current)
        end
      end
    end

    def block_claim!(id:, token:)
      AiAutomationWorkItem.transaction do
        item = AiAutomationWorkItem.lock.find_by(id: id)
        return unless item && item.state == "leased" && item.lease_token == token
        item.update!(state: "blocked", lease_token: nil, lease_until: nil,
          failure_code: "consent_or_source_changed")
      end
    end

    def validate_lease!(item, token)
      unless item.state == "leased" && item.lease_token == token &&
          item.lease_until && item.lease_until > Time.current
        raise Errors::InvalidSelection, "Expired or invalid work lease"
      end
    end
  end
end
