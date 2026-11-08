# frozen_string_literal: true

module AiWorkspace
  # An explicit, bounded, room-local selection. This is a READ-ONLY privacy
  # preview, not a model prompt and not a provider submission.
  class Scope
    OPERATIONS = {
      "summarize" => "Summarize",
      "translate" => "Translate",
      "suggest_reply" => "Suggest a reply"
    }.freeze
    MAX_MESSAGES = 8
    MAX_MESSAGE_CHARS = 750

    class Unauthorized < StandardError; end
    class InvalidSelection < StandardError; end

    Row = Struct.new(:message_id, :author, :text, :truncated, keyword_init: true)
    Preview = Struct.new(:operation, :rows, :characters, keyword_init: true)

    def initialize(room:, actor:, operation:, message_ids:)
      @room = room
      @actor = actor
      @operation = operation.to_s
      @message_ids = message_ids
    end

    def review
      # Recheck membership immediately before retrieving the selected data,
      # even when the controller previously authenticated the request.
      raise Unauthorized unless @room.accessible_to?(@actor)
      raise InvalidSelection, "Choose a valid AI task." unless OPERATIONS.key?(@operation)
      unless @message_ids.is_a?(Array) && @message_ids.length.between?(1, MAX_MESSAGES)
        raise InvalidSelection, "Select between 1 and #{MAX_MESSAGES} text messages."
      end

      ids = @message_ids.map do |value|
        unless value.is_a?(String) && value.match?(/\A[1-9]\d{0,17}\z/)
          raise InvalidSelection, "Invalid message selection."
        end
        value.to_i
      end
      raise InvalidSelection, "Each message may be selected once." unless ids.uniq.size == ids.size

      # Resolve IDs from THIS room only. Do not query global Message.find.
      by_id = @room.messages.where(id: ids).includes(:user).index_by(&:id)
      raise InvalidSelection, "Selected message is unavailable in this room." unless by_id.size == ids.size

      selected = ids.map { |id| by_id.fetch(id) }
      raise InvalidSelection, "Only text messages can be reviewed." if selected.any? { |m| m.body.to_s.strip.empty? }

      # Preserve chronology, independent of client-provided ID order.
      selected.sort_by! { |m| [m.created_at, m.id] }
      rows = selected.map do |message|
        text = message.body.to_s.strip
        Row.new(
          message_id: message.id,
          author: message.user.chat_label,
          text: text[0, MAX_MESSAGE_CHARS],
          truncated: text.length > MAX_MESSAGE_CHARS
        )
      end
      Preview.new(operation: @operation, rows: rows, characters: rows.sum { |row| row.text.length })
    end
  end
end
