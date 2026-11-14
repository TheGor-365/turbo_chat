module MessagesHelper
  # Show the matching text in context rather than blindly truncating from
  # the beginning. Every segment is escaped by Rails; only <mark> is HTML.
  def message_search_excerpt(body, query)
    text = body.to_s
    match_at = text.downcase.index(query.to_s.downcase) || 0
    start_at = [match_at - 65, 0].max
    end_at = [start_at + 200, text.length].min
    excerpt = text[start_at...end_at].to_s

    parts = excerpt.split(/(#{Regexp.escape(query)})/i)
    rendered = parts.map do |part|
      if part.casecmp?(query)
        content_tag(:mark, part, class: "message-search-highlight")
      else
        part
      end
    end

    rendered.unshift("…") if start_at.positive?
    rendered.push("…") if end_at < text.length
    safe_join(rendered)
  end

  # Safe Markdown-lite for messages. All non-markup fragments are escaped
  # using Rails tags/safe_join. Stored message bodies are never rewritten.
  def render_message_body(body)
    blocks = []
    items = []
    list_type = nil
    code_lines = nil
    flush = lambda do
      next if items.empty?

      list = safe_join(items.map { |item| tag.li(item) })
      blocks << (list_type == :ordered ? tag.ol(list) : tag.ul(list))
      items = []
      list_type = nil
    end

    body.to_s.gsub(/\r\n?/, "\n").split("\n", -1).each do |line|
      if code_lines
        if line.match?(/\A\x60{3}\s*\z/)
          blocks << tag.pre(tag.code(code_lines.join("\n")))
          code_lines = nil
        else
          code_lines << line
        end
        next
      end

      if line.match?(/\A\x60{3}[a-zA-Z0-9_-]*\s*\z/)
        flush.call
        code_lines = []
      elsif line.strip.empty?
        flush.call
      elsif (m = line.match(/\A {0,3}[-*]\s+(.+)\z/))
        flush.call if list_type != :unordered
        list_type = :unordered
        items << render_message_inline(m[1])
      elsif (m = line.match(/\A {0,3}\d{1,2}[.)]\s+(.+)\z/))
        flush.call if list_type != :ordered
        list_type = :ordered
        items << render_message_inline(m[1])
      else
        flush.call
        if (m = line.match(/\A {0,3}[#]{1,3}\s+(.+)\z/))
          blocks << tag.h6(render_message_inline(m[1]))
        else
          blocks << tag.p(render_message_inline(line))
        end
      end
    end
    flush.call
    blocks << tag.pre(tag.code(code_lines.join("\n"))) if code_lines
    tag.div(safe_join(blocks), class: "sd-message-rich")
  end

  private

  # Links/images/raw HTML are intentionally not parsed; source IDs are
  # non-clickable annotations unless separately authorized in the room.
  def render_message_inline(value)
    tokens = value.to_s.split(/(\*\*[^*\n]+\*\*|\x60[^\x60\n]+\x60|\*[^*\n]+\*|\[M[1-9]\d{0,17}\])/)
    safe_join(tokens.map do |token|
      case token
      when /\A\*\*([^*\n]+)\*\*\z/
        tag.strong(Regexp.last_match(1))
      when /\A\x60([^\x60\n]+)\x60\z/
        tag.code(Regexp.last_match(1))
      when /\A\*([^*\n]+)\*\z/
        tag.em(Regexp.last_match(1))
      when /\A\[M[1-9]\d{0,17}\]\z/
        tag.span(token, class: "sd-message-source-ref", title: "Message reference")
      else
        token
      end
    end)
  end

end
