# frozen_string_literal: true

require "digest"
require "json"

module AiWorkspace
  # Captures idempotent metadata snapshots for later, separately authorized
  # workers. No ActiveJob enqueue, model inference, message Send, or export.
  # Existing manual room consent is NOT authorization for unattended AI.
  class AutomationRunRegistry
    class Unavailable < StandardError; end

    def initialize(access: RoomContextAccess.new, builder: ReplyContextBuilder.new)
      @access = access
      @builder = builder
    end

    # "review" => future Apply-only proposal; "full_auto" => metadata only,
    # never permission to post. Dedupes one unchanged inbound per policy/goal revision.
    def capture_incoming!(room:, actor:, incoming:)
      raise Unavailable, "Missing durable event" unless incoming&.persisted?

      room.with_lock do
        policy = permitted_policy!(room: room.reload, actor: actor)
        kind = case policy.reply_mode
        when "review" then "reply_proposal"
        when "full_auto" then "reply_unattended"
        else raise Unavailable, "Reply automation is off"
        end

        goal = AiConversationGoal.find_by(room: room, user: actor, active: true)
        raise Unavailable, "Personal conversation goal required" unless goal

        # This guard validates context visibility for metadata capture only.
        # An unattended processing grant will be a distinct future consent.
        @access.authorize!(room: room, actor: actor)
        fresh = room.messages.find_by(id: incoming.id)
        raise Unavailable, "Source is unavailable" unless fresh &&
          fresh.user_id != actor.id &&
          room.participants.exists?(user_id: fresh.user_id) &&
          fresh.body.present?

        fingerprint = AutomationSourceFingerprint.incoming(fresh)
        key = digest("reply", room.id, actor.id, kind, fresh.id, fingerprint,
          policy.revision, goal.revision)

        AiAutomationRun.find_or_create_by!(event_key: key) do |run|
          run.assign_attributes(room: room, user: actor,
            ai_automation_policy: policy, run_kind: kind,
            trigger_message: fresh, source_message_ids: [fresh.id],
            source_fingerprint: fingerprint, policy_revision: policy.revision,
            goal_revision: goal.revision, status: "recorded")
        end
      end
    end

    # A "daily:YYYY-MM-DD" or "after_messages:<cursor>" key identifies one
    # reporting window. A changed source is never silently substituted into
    # an earlier run: later execution must re-authorize and re-fingerprint.
    def capture_outcome!(room:, actor:, window_key:, after_message_id: nil,
      through_message_id: nil, utc_day: nil)
      unless window_key.is_a?(String) &&
          window_key.match?(/\A(?:daily:\d{4}-\d{2}-\d{2}|after_messages:[1-9]\d{0,17}|manual:[a-z0-9_-]{8,64})\z/)
        raise Unavailable, "Invalid reporting window"
      end

      room.with_lock do
        policy = permitted_policy!(room: room.reload, actor: actor)
        unless %w[manual after_messages daily].include?(policy.summary_mode) &&
            (policy.summary_mode == "manual" ? window_key.start_with?("manual:") :
              window_key.start_with?("#{policy.summary_mode}:"))
          raise Unavailable, "Summary automation is off or window mismatched"
        end

        # This only stages a fingerprint, never starts a scheduled job.
        bundle = @builder.build(room: room, actor: actor,
          after_message_id: after_message_id,
          through_message_id: through_message_id, utc_day: utc_day)
        fingerprint = AutomationSourceFingerprint.outcome(bundle)
        key = digest("outcome", room.id, actor.id, window_key,
          policy.summary_kind, policy.revision)

        AiAutomationRun.find_or_create_by!(event_key: key) do |run|
          run.assign_attributes(room: room, user: actor,
            ai_automation_policy: policy, run_kind: "conversation_outcome",
            source_message_ids: bundle.source_ids, source_fingerprint: fingerprint,
            source_after_message_id: after_message_id,
            source_through_message_id: through_message_id, source_utc_day: utc_day,
            policy_revision: policy.revision, status: "recorded")
        end
      end
    end

    private

    def permitted_policy!(room:, actor:)
      raise Errors::Unauthorized, "Private membership required" unless
        actor&.persisted? && room.is_private? && room.accessible_to?(actor)

      policy = AiAutomationPolicy.find_by(room: room, user: actor)
      raise Unavailable, "No automation configuration" unless policy
      policy
    end

    def digest(*items)
      Digest::SHA256.hexdigest(JSON.generate(items))
    end
  end
end
