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
end
