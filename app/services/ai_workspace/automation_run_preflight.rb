# frozen_string_literal: true

module AiWorkspace
  # Read-only staleness audit for journal entries. Passing it DOES NOT grant
  # unattended model access, provider spending or permission to send.
  # The real worker must introduce separate execution consent and hard budget.
  class AutomationRunPreflight
    Result = Struct.new(:current, :execution_authorized, :run_id,
      :policy_revision, :source_message_ids, keyword_init: true)

    def initialize(access: RoomContextAccess.new, builder: ReplyContextBuilder.new)
      @access = access
      @builder = builder
    end

    def check!(run:)
      raise Errors::InvalidSelection, "Invalid automation run" unless run.is_a?(AiAutomationRun)

      room = run.room
      actor = run.user
      room.with_lock do
        room.reload
        run.reload
        raise Errors::InvalidSelection, "Recorded event is no longer active" unless
          run.status == "recorded"
        raise Errors::Unauthorized, "Private membership required" unless
          room.is_private? && room.accessible_to?(actor)

        policy = AiAutomationPolicy.find_by(id: run.ai_automation_policy_id,
          room: room, user: actor)
        unless policy && policy.revision == run.policy_revision
          raise Errors::InvalidSelection, "Automation policy changed"
        end

        # Manual consent here only limits metadata checks; it NEVER upgrades
        # the scope to unattended external processing.
        @access.authorize!(room: room, actor: actor)
        verify_sources!(run: run, room: room, actor: actor, policy: policy)

        Result.new(current: true, execution_authorized: false, run_id: run.id,
          policy_revision: policy.revision,
          source_message_ids: run.source_message_ids.dup.freeze).freeze
      end
    end

    private

    def verify_sources!(run:, room:, actor:, policy:)
      case run.run_kind
      when "reply_proposal", "reply_unattended"
        expected_mode = run.run_kind == "reply_proposal" ? "review" : "full_auto"
        raise Errors::InvalidSelection, "Reply mode changed" unless policy.reply_mode == expected_mode

        goal = AiConversationGoal.find_by(room: room, user: actor, active: true)
        unless goal && goal.revision == run.goal_revision
          raise Errors::InvalidSelection, "Conversation goal changed"
        end

        source = room.messages.find_by(id: run.trigger_message_id)
        unless source && source.user_id != actor.id &&
            room.participants.exists?(user_id: source.user_id) &&
            run.source_message_ids == [source.id] &&
            source.body.present? &&
            AutomationSourceFingerprint.incoming(source) == run.source_fingerprint
          raise Errors::InvalidSelection, "Incoming message has changed"
        end
      when "conversation_outcome"
        raise Errors::InvalidSelection, "Outcome automation is disabled" unless
          %w[manual after_messages daily].include?(policy.summary_mode)

        bundle = @builder.build(room: room, actor: actor, **run.outcome_source_options)
        unless bundle.source_ids == run.source_message_ids &&
            AutomationSourceFingerprint.outcome(bundle) == run.source_fingerprint
          raise Errors::InvalidSelection, "Conversation evidence has changed"
        end
      else
        raise Errors::InvalidSelection, "Unknown automation event"
      end
    end
  end
end
