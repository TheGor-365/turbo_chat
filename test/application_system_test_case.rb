require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000]

  # Capybara named sessions (e.g. :bob) outlive an individual Rails system
  # test. Clear every browser context between scenarios, not only :default.
  setup { Capybara.reset_sessions! }
end
