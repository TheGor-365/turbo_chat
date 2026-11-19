# frozen_string_literal: true

module AiWorkspace
  # Bounded, deterministic comparison of two saved document revisions.
  # Exact text lines only; never claims semantic equivalence or approval.
  class SavedRevisionDiffV1
    MAX_LINES = 160

    Result = Struct.new(:rows, :added, :removed, :unchanged, keyword_init: true)
    Row = Struct.new(:status, :text, keyword_init: true)

    def self.compare!(before:, after:)
      original = lines!(before)
      proposed = lines!(after)
      # Small bounded LCS. Stable tie-breaking makes diffs repeatable.
      dp = Array.new(original.length + 1) { Array.new(proposed.length + 1, 0) }
      (original.length - 1).downto(0) do |i|
        (proposed.length - 1).downto(0) do |j|
          dp[i][j] = if original[i] == proposed[j]
            1 + dp[i + 1][j + 1]
          else
            [dp[i + 1][j], dp[i][j + 1]].max
          end
        end
      end
      i = j = 0
      rows = []
      while i < original.length || j < proposed.length
        if i < original.length && j < proposed.length && original[i] == proposed[j]
          rows << Row.new(status: "unchanged", text: original[i])
          i += 1
          j += 1
        elsif j < proposed.length && (i == original.length || dp[i][j + 1] >= dp[i + 1][j])
          rows << Row.new(status: "added", text: proposed[j])
          j += 1
        else
          rows << Row.new(status: "removed", text: original[i])
          i += 1
        end
      end
      Result.new(rows: rows.freeze,
        added: rows.count { |row| row.status == "added" },
        removed: rows.count { |row| row.status == "removed" },
        unchanged: rows.count { |row| row.status == "unchanged" })
    end

    def self.lines!(text)
      raise ArgumentError, "Invalid revision" unless text.is_a?(String) &&
        text.valid_encoding? && text.length <= 5_000
      lines = text.gsub(/\r\n?/, "\n").lines(chomp: true)
      raise ArgumentError, "Too many revision lines" if lines.size > MAX_LINES
      lines
    end

    private_class_method :lines!
  end
end
