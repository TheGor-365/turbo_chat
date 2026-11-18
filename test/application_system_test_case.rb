require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000]

  # Capybara named sessions (e.g. :bob) outlive an individual Rails system
  # test. Clear every browser context between scenarios, not only :default.
  setup { Capybara.reset_sessions! }

  # Writing style now starts collapsed in both panels. A system test that
  # needs the choices must reveal them as a real user would.
  def expand_ai_style(panel)
    selector = case panel
    when :draft then "#ai-draft-panel .sd-ai-style-details"
    when :room then "#ai-room-settings .sd-ai-room-style-picker"
    else raise ArgumentError, "Unknown AI panel"
    end
    assert_selector selector
    unless has_css?("#{selector}[open]", visible: :all)
      find("#{selector} > summary").click
    end
    assert_selector "#{selector}[open]"
  end
end
