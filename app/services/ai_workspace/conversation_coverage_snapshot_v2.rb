# frozen_string_literal: true

require "digest"

module AiWorkspace
  # FCC-2a. Read-only, consent-scoped, bounded source-version inventory.
  #
  # One PostgreSQL SELECT statement provides an MVCC-consistent source view.
  # A second statement compares the *whole* authorized source signature,
  # including content digests, to invalidate observed edits and deletes.
  #
  # This is NOT a durable authorization token, provider context bundle,
  # cross-transaction lock, or guarantee against a mutation after return.
  # Never hand these source IDs to a provider without a fresh consent,
  # membership, budget and source revalidation gate.
  class ConversationCoverageSnapshotV2
    VERSION = 2
    MAX_MESSAGES = ConversationCoverageV1::MAX_MESSAGES

    SourceVersion = Struct.new(:message_id, :author_id, :updated_at,
      :body_sha256, :version_sha256, keyword_init: true)
    Report = Struct.new(:version, :room_id, :actor_id, :watermark_message_id,
      :total_messages, :current_author_messages, :included_text_messages,
      :excluded_departed_author, :excluded_non_text, :excluded_sensitive,
      :excluded_invalid, :excluded_withheld_author, :source_sha256, :consent_sha256, :sources,
      keyword_init: true)

    def initialize(access: RoomContextAccess.new, max_messages: MAX_MESSAGES)
      unless max_messages.instance_of?(Integer) && max_messages.between?(1, MAX_MESSAGES)
        raise ArgumentError, "Invalid snapshot limit."
      end
      @access = access
      @max_messages = max_messages
    end

    def build(room:, actor:)
      ActiveRecord::Base.uncached do
        build_snapshot(room: room, actor: actor)
      end
    end

    private

    def build_snapshot(room:, actor:)
      @access.authorize!(room: room, actor: actor)
      member_ids = room.participants.distinct.pluck(:user_id).sort.freeze
      raise Errors::Unauthorized, "Conversation unavailable." unless member_ids.include?(actor.id)

      grants = consent_signature(room: room, member_ids: member_ids)
      allowed_ids = granted_author_ids(grants)
      rows = read_source_statement(room: room, member_ids: allowed_ids)
      reject_oversized!(rows)
      signature = rows_signature(rows, room_id: room.id, member_ids: member_ids)
      categories, sources = classify(rows, member_ids: member_ids, allowed_ids: allowed_ids)
      after_snapshot(room: room, actor: actor)

      # A second full statement detects a changed body even when updated_at
      # was bypassed using update_columns. Counts alone cannot catch edits.
      room.reload
      @access.authorize!(room: room, actor: actor)
      unless room.participants.distinct.pluck(:user_id).sort == member_ids &&
          consent_signature(room: room, member_ids: member_ids) == grants
        raise Errors::InvalidSelection, "Permissions changed during coverage snapshot."
      end

      validation_rows = read_source_statement(room: room, member_ids: allowed_ids)
      reject_oversized!(validation_rows)
      unless rows_signature(validation_rows, room_id: room.id,
        member_ids: member_ids) == signature
        raise Errors::InvalidSelection, "Conversation changed during coverage snapshot."
      end

      # Close a consent/membership change observed during the second pass.
      @access.authorize!(room: room, actor: actor)
      unless room.participants.distinct.pluck(:user_id).sort == member_ids &&
          consent_signature(room: room, member_ids: member_ids) == grants
        raise Errors::InvalidSelection, "Permissions changed during coverage snapshot."
      end

      Report.new(version: VERSION, room_id: room.id, actor_id: actor.id,
        watermark_message_id: rows.last&.first.to_i,
        total_messages: rows.size,
        current_author_messages: rows.count { |row| member_ids.include?(row[1]) },
        included_text_messages: sources.size,
        excluded_departed_author: categories.fetch(:departed),
        excluded_withheld_author: categories.fetch(:withheld),
        excluded_non_text: categories.fetch(:non_text),
        excluded_sensitive: categories.fetch(:sensitive),
        excluded_invalid: categories.fetch(:invalid),
        source_sha256: signature.freeze,
        consent_sha256: Digest::SHA256.hexdigest(grants.inspect).freeze,
        sources: sources.freeze).freeze
    end

    def read_source_statement(room:, member_ids:)
      # CASE returns NULL for former authors and authors without active grants. Build the predicate with Arel
      # nodes, never interpolated SQL; IDs are captured by the consent gate.
      messages = Message.arel_table
      masked_body = Arel::Nodes::Case.new
        .when(messages[:user_id].in(member_ids))
        .then(messages[:body])
        .else(nil)
      room.messages.order(:id).limit(@max_messages + 1)
        .pluck(:id, :user_id, masked_body, :updated_at)
    end

    def reject_oversized!(rows)
      return if rows.size <= @max_messages

      raise Errors::InvalidSelection, "History exceeds the coverage snapshot limit."
    end

    def consent_signature(room:, member_ids:)
      AiRoomContextConsent.where(room_id: room.id, user_id: member_ids)
        .order(:user_id).pluck(:user_id, :granted_at, :revoked_at, :updated_at)
    end

    def granted_author_ids(grants)
      grants.filter_map do |id, granted_at, revoked_at, _updated_at|
        id if granted_at.present? && revoked_at.nil?
      end.freeze
    end

    def rows_signature(rows, room_id:, member_ids:)
      sha = Digest::SHA256.new
      sha.update("fcc2:#{room_id}:#{member_ids.join(',')}\n")
      rows.each do |id, author_id, body, updated_at|
        sha.update("#{id}:#{author_id}:#{updated_at&.utc&.iso8601(6)}:")
        sha.update(Digest::SHA256.hexdigest(body.to_s))
        sha.update("\n")
      end
      sha.hexdigest
    end

    def classify(rows, member_ids:, allowed_ids:)
      categories = { departed: 0, withheld: 0, non_text: 0, sensitive: 0, invalid: 0 }
      sources = []
      rows.each do |id, author_id, body, updated_at|
        unless member_ids.include?(author_id)
          categories[:departed] += 1
          next
        end
        unless allowed_ids.include?(author_id)
          categories[:withheld] += 1
          next
        end
        if body.blank?
          categories[:non_text] += 1
          next
        end
        begin
          normalized = Preprocessors::Text.call(body)
          if normalized.warnings.any?
            categories[:sensitive] += 1
            next
          end
          if normalized.text.strip.empty?
            categories[:non_text] += 1
            next
          end
          body_hash = Digest::SHA256.hexdigest(body)
          version_hash = Digest::SHA256.hexdigest(
            "#{id}:#{author_id}:#{updated_at&.utc&.iso8601(6)}:#{body_hash}"
          )
          sources << SourceVersion.new(message_id: id, author_id: author_id,
            updated_at: updated_at&.utc&.iso8601(6)&.freeze,
            body_sha256: body_hash.freeze, version_sha256: version_hash.freeze).freeze
        rescue Errors::InvalidSelection
          categories[:invalid] += 1
        end
      end
      [categories.freeze, sources]
    end

    # Deterministic test seam. No side effects in production.
    def after_snapshot(room:, actor:); end
  end
end
