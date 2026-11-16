require "application_system_test_case"

class AiCoveragePreviewSystemTest < ApplicationSystemTestCase
  def login(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def private_room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  def grant_all(room)
    [users(:one), users(:two)].each do |user|
      AiRoomContextConsent.find_or_initialize_by(room: room, user: user).grant!
    end
  end

  def open_coverage
    click_button "Edit unsent message"
    find("#ai-draft-panel .sd-ai-source-review > summary").click
    find("#ai-draft-panel .sd-ai-coverage > summary").click
    assert_selector "#ai-draft-panel .sd-ai-coverage[open]"
  end

  test "coverage is manual, safe, accurate, and does not alter an unsent message" do
    room = private_room
    grant_all(room)
    first = room.messages.create!(user: users(:two), body: "The draft price is not confirmed.")
    second = room.messages.create!(user: users(:one), body: "Clarify the scope.")
    login(users(:one))

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      visit room_path(room, ui_locale: :en)
      fill_in "chat-text", with: "This unsent draft must remain untouched."
      open_coverage
      page.execute_script(<<~JS)
        window.__coverageRequestCount = 0
        window.__nativeCoverageFetch = window.fetch
        window.fetch = (url, options) => {
          if (String(url).includes("/ai/coverage-preview")) window.__coverageRequestCount += 1
          return window.__nativeCoverageFetch(url, options)
        }
      JS
      assert_equal 0, page.evaluate_script("window.__coverageRequestCount")
      assert_no_selector "#ai-draft-panel .sd-ai-coverage__metrics > div", visible: :all

      within "#ai-draft-panel .sd-ai-coverage" do
        click_button "Check history"
        assert_selector ".sd-ai-coverage__status", text: "Nothing was sent to AI.", wait: 10
        assert_selector ".sd-ai-coverage__metrics > div", count: 3
        assert_selector ".sd-ai-coverage__metrics", text: "Total messages"
        assert_selector ".sd-ai-coverage__metrics", text: "Eligible sources"
        assert_selector ".sd-ai-coverage__metrics", text: "2"
        assert_selector ".sd-ai-coverage__details a[href*='focus=#{first.id}']"
        assert_selector ".sd-ai-coverage__details a[href*='focus=#{second.id}']"
        assert_no_text "The draft price is not confirmed."
      end
      assert_equal 1, page.evaluate_script("window.__coverageRequestCount")
      assert_field "chat-text", with: "This unsent draft must remain untouched."
      assert_equal 2, room.messages.count

      find("#ai-draft-panel .sd-ai-coverage > summary").click
      assert_selector "#ai-draft-panel .sd-ai-coverage__results[hidden]", visible: :all
      find("#ai-draft-panel .sd-ai-coverage > summary").click
      assert_equal 1, page.evaluate_script("window.__coverageRequestCount")
      assert_selector "#ai-draft-panel .sd-ai-coverage__metrics:empty", visible: :all
    end
  end

  test "only explicit next-page clicks retrieve additional eligible sources" do
    room = private_room
    grant_all(room)
    26.times { |index| room.messages.create!(user: users(:two), body: "Checkpoint #{index}") }
    login(users(:one))

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      visit room_path(room, ui_locale: :en)
      open_coverage
      within "#ai-draft-panel .sd-ai-coverage" do
        click_button "Check history"
        assert_selector ".sd-ai-coverage__page", text: "Page 1 of 2", wait: 10
        assert_selector ".sd-ai-coverage__details ol li", count: 25
        click_button "Next page"
        assert_selector ".sd-ai-coverage__page", text: "Page 2 of 2", wait: 10
        assert_selector ".sd-ai-coverage__details ol li", count: 26
        assert_no_button "Next page", visible: true
      end
      assert_equal 26, room.messages.count
    end
  end

  test "missing member consent shows safe error and does not trigger Grok" do
    room = private_room
    room.messages.create!(user: users(:two), body: "Private source only")
    login(users(:one))

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      visit room_path(room, ui_locale: :en)
      open_coverage
      within "#ai-draft-panel .sd-ai-coverage" do
        click_button "Check history"
        assert_selector ".sd-ai-coverage__status", text: "Preview unavailable.", wait: 10
        assert_selector ".sd-ai-coverage__results[hidden]", visible: :all
        assert_no_text "Private source only"
      end
      assert_equal 1, room.messages.count
    end
  end

  test "coverage cards remain inside narrow mobile editor" do
    original_size = page.current_window.size
    room = private_room
    grant_all(room)
    3.times { |i| room.messages.create!(user: users(:two), body: "Scope #{i}") }
    page.current_window.resize_to(390, 800)
    login(users(:one))

    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      visit room_path(room, ui_locale: :en)
      open_coverage
      click_button "Check history"
      assert_selector "#ai-draft-panel .sd-ai-coverage__metrics > div", count: 3, wait: 10
      fits = page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector("#ai-draft-panel")
          const coverage = panel.querySelector(".sd-ai-coverage")
          const bounds = coverage.getBoundingClientRect()
          const parent = coverage.parentElement.getBoundingClientRect()
          return bounds.width <= parent.width + 1 &&
            coverage.scrollWidth <= coverage.clientWidth + 1
        })()
      JS
      assert_equal true, fits
    end
  ensure
    page.current_window.resize_to(original_size.width, original_size.height)
  end
end
