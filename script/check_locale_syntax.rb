# frozen_string_literal: true

# Independent preboot syntax check: Rails and I18n cannot start with even one
# malformed locale. Run before bundle, assets, database and system tests.
require "psych"

root = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "config/locales/**/*.{yml,yaml}")).sort
abort "No locale YAML files found" if files.empty?

errors = []
files.each do |path|
  begin
    document = Psych.parse_file(path)
    raise ArgumentError, "expected top-level mapping" unless
      document&.root.is_a?(Psych::Nodes::Mapping)
  rescue Psych::SyntaxError, ArgumentError => error
    errors << "#{path.delete_prefix(root + "/")}: #{error.message}"
  end
end

if errors.any?
  warn "Invalid locale YAML (#{errors.size} of #{files.size} files):"
  errors.each { |error| warn " - #{error}" }
  exit 1
end

puts "Locale syntax OK: #{files.size} YAML files"
