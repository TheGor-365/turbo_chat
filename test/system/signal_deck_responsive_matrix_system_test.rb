require "application_system_test_case"

class SignalDeckResponsiveMatrixSystemTest < ApplicationSystemTestCase
  def sign_in_for_qa(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def assert_no_document_overflow(width, description)
    geometry = page.evaluate_script(<<~JS)
      (() => ({
        viewport: window.innerWidth,
        document: document.documentElement.scrollWidth,
        body: document.body.scrollWidth
      }))()
    JS
    assert_operator geometry.fetch("document"), :<=, geometry.fetch("viewport") + 1,
      "#{description} at #{width}px overflowed document: #{geometry.inspect}"
  end

  test "core signed-in routes remain contained across release viewport widths" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in_for_qa(alice)

    [320, 390, 768, 1024, 1440].each do |width|
      page.current_window.resize_to(width, 900)
      [
        [root_path, ".sd-home-hero"],
        [edit_user_registration_path, ".sd-account-page"],
        [rooms_path, "#side_panel"],
        [room_path(room), "#messages-container"],
        [notifications_path, "#archive-search"]
      ].each do |path, target|
        visit path
        assert_selector target, visible: true
        assert_no_document_overflow(width, path)
      end
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "mobile archive controls are keyboard accessible with sufficiently large targets" do
    page.current_window.resize_to(390, 844)
    sign_in_for_qa(users(:one))
    visit notifications_path
    assert_selector ".sd-archive-kind", count: 7
    assert_selector ".sd-archive-kinds", visible: true
    assert_selector ".sd-mobile-bottom-nav--activity", visible: true
    assert_selector ".sd-activity-header h1", text: "Activity & history"

    selectors = [
      ".sd-activity-back", ".sd-archive-kind",
      ".sd-archive-submit", ".sd-archive-control--room .sd-archive-picker__trigger"
    ]
    selectors.each do |selector|
      rect = page.evaluate_script(<<~JS)
        (() => {
          const box = document.querySelector("#{selector}").getBoundingClientRect()
          return { width: box.width, height: box.height }
        })()
      JS
      assert_operator rect.fetch("height"), :>=, 43.5, "#{selector} target too short"
      assert_operator rect.fetch("width"), :>=, 43.5, "#{selector} target too narrow"
    end

    assert_no_document_overflow(390, "activity filter rail")
    # B14: all seven archive types fit on exactly two non-scrolling tile rows.
    tiles = page.evaluate_script(<<~JS)
      (() => {
        const nav = document.querySelector('.sd-archive-kinds')
        const buttons = [...nav.querySelectorAll('.sd-archive-kind')]
        return {rows: new Set(buttons.map(el => Math.round(el.getBoundingClientRect().top))).size,
          hasHorizontalOverflow: nav.scrollWidth > nav.clientWidth + 1,
          targets: buttons.every(el => el.getBoundingClientRect().width >= 43.5 &&
            el.getBoundingClientRect().height >= 43.5)}
      })()
    JS
    assert_equal 2, tiles.fetch("rows")
    assert_equal false, tiles.fetch("hasHorizontalOverflow")
    assert_equal true, tiles.fetch("targets")

    %w[dark light system].each do |mode|
      assert_selector "html[data-theme='#{mode}']", visible: :all if mode == "dark"
      current = page.evaluate_script("document.documentElement.dataset.theme")
      while current != mode
        find(".sd-nav__account > summary").click unless page.has_css?(".sd-nav__account[open]")
        find(".sd-nav__account-menu button[data-theme-target='toggle']").click
        current = page.evaluate_script("document.documentElement.dataset.theme")
      end
      assert_selector "html[data-theme='#{mode}']", visible: :all
      assert_no_document_overflow(390, "activity #{mode} theme")
    end

    page.execute_script("document.querySelector('.sd-skip-link').focus()")
    assert_equal true, page.evaluate_script(
      "document.activeElement.classList.contains('sd-skip-link')")
    find(".sd-skip-link").send_keys(:enter)
    assert_equal "main-content", page.evaluate_script(
      "document.activeElement.id")
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
