# frozen_string_literal: true

require "digest"

module AiWorkspace
  # Opt-in non-AI fixture for exercising the saved proposal -> Apply route.
  # This class NEVER makes a provider call, charges usage, queues work or Sends.
  # A future S3/S6 verified model producer must be separate from this path.
  class OfflineReplyProposal
    class Unavailable < StandardError; end

    TEMPLATES = {
      "en" => "Thanks for your message. Could you clarify the expected outcome so I can respond accurately?",
      "ru" => "Спасибо за сообщение. Уточните, пожалуйста, какой результат вы ожидаете, чтобы я мог ответить точнее.",
      "hy" => "Շնորհակալություն հաղորդագրության համար։ Կարո՞ղ եք հստակեցնել սպասվող արդյունքը, որպեսզի ճշգրիտ պատասխանեմ։",
      "es" => "Gracias por tu mensaje. ¿Podrías aclarar el resultado esperado para que pueda responder con precisión?"
    }.freeze

    def initialize(registry: AutomationRunRegistry.new,
      preflight: AutomationRunPreflight.new,
      consent: AutomationConsentGate.new,
      builder: ReplyContextBuilder.new)
      @registry, @preflight, @consent, @builder = registry, preflight, consent, builder
    end

    def create!(room:, actor:, language: "en")
      raise Unavailable, "Unsupported language" unless TEMPLATES.key?(language)
      room.with_lock do
        @consent.check!(room: room.reload, actor: actor, mode: "review")
        policy = AiAutomationPolicy.find_by(room: room, user: actor)
        raise Unavailable, "Review policy is disabled" unless policy&.reply_mode == "review"

        # Reuse the protected, DLP-filtered source selector; never use raw
        # browser-provided message content as proof of model generation.
        bundle = @builder.build(room: room, actor: actor)
        incoming_row = bundle.rows.reverse.find { |row| row.speaker != "you" }
        raise Unavailable, "No safe inbound message" unless incoming_row
        incoming = room.messages.find_by(id: incoming_row.message_id)
        raise Unavailable, "Source no longer exists" unless incoming
        # A message edit can occur after the bounded retrieval. Re-check DLP
        # on its CURRENT full body before persisting any source attestation.
        safe = Preprocessors::Text.call(incoming.body)
        unless safe.warnings.empty? && safe.text.strip.start_with?(incoming_row.text)
          raise Unavailable, "Incoming source changed or became unsafe"
        end

        run = @registry.capture_incoming!(room: room, actor: actor, incoming: incoming)
        @preflight.check!(run: run)
        text = TEMPLATES.fetch(language)
        AiReplyProposal.find_or_create_by!(ai_automation_run: run) do |proposal|
          proposal.assign_attributes(room: room, user: actor, origin: "offline_template",
            state: "pending", body: text, body_sha256: Digest::SHA256.hexdigest(text))
        end
      end
    end

    def latest!(room:, actor:)
      raise Errors::Unauthorized, "Private membership required" unless
        room.is_private? && room.accessible_to?(actor)
      proposal = AiReplyProposal.where(room: room, user: actor)
        .where.not(state: "dismissed").order(id: :desc).first
      return nil unless proposal

      authorize!(proposal: proposal, actor: actor)
      proposal
    end

    def apply!(proposal:, actor:)
      decide!(proposal: proposal, actor: actor, state: "applied")
    end

    def dismiss!(proposal:, actor:)
      decide!(proposal: proposal, actor: actor, state: "dismissed")
    end

    def authorize!(proposal:, actor:)
      raise Errors::Unauthorized, "Not your private proposal" unless
        proposal.user_id == actor.id && proposal.room.is_private? &&
        proposal.room.accessible_to?(actor)
      @preflight.check!(run: proposal.ai_automation_run)
      @consent.check!(room: proposal.room, actor: actor, mode: "review")
      raise Unavailable, "Stored suggestion no longer matches" unless
        Digest::SHA256.hexdigest(proposal.body) == proposal.body_sha256
      true
    end

    private

    def decide!(proposal:, actor:, state:)
      proposal.room.with_lock do
        saved = AiReplyProposal.lock.find(proposal.id)
        authorize!(proposal: saved, actor: actor)
        raise Unavailable, "Proposal was dismissed" if saved.state == "dismissed"
        if state == "dismissed"
          raise Unavailable, "Already applied" if saved.state == "applied"
          saved.update!(state: "dismissed", dismissed_at: Time.current)
        elsif state == "applied"
          saved.update!(state: "applied", applied_at: Time.current) if saved.state == "pending"
        else
          raise Unavailable, "Unknown decision"
        end
        saved
      end
    end
  end
end
