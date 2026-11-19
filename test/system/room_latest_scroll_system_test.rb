require "application_system_test_case"

class RoomLatestScrollSystemTest < ApplicationSystemTestCase
  def setup
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    30.times do |i|
      @room.messages.create!(user: i.even? ? @alice : @bob,
        body: "Rails request #{i}: review the acceptance criteria and respond to the participant. " * 2)
    end
  end

  def open_room
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: @alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit room_path(@room, ui_locale: :en)
    assert_selector "#messages[data-scroll-phase='ready']", wait: 10
    assert_operator page.evaluate_script(
      "document.querySelector('#messages').scrollHeight - document.querySelector('#messages').clientHeight"), :>, 200
  end

  def distance_from_bottom
    page.evaluate_script(<<~JS)
      (() => {
        const s = document.querySelector('#messages')
        return s.scrollHeight - s.scrollTop - s.clientHeight
      })()
    JS
  end

  test "first room load lands at latest and follows late content growth" do
    open_room
    assert_operator distance_from_bottom, :<=, 5
    page.execute_script("document.querySelector('#messages-container').lastElementChild.style.paddingBottom = '350px'")
    # ResizeObserver runs on the next browser rendering opportunity.
    # Wait for actual scroll anchoring, not an unrelated already-ready marker.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while distance_from_bottom > 5 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.04
    end
    assert_operator distance_from_bottom, :<=, 5
    assert_equal 30, @room.messages.count
  end

  test "reading old messages disables initial automatic follow" do
    open_room
    page.execute_script(<<~JS)
      const scroller = document.querySelector('#messages')
      scroller.dispatchEvent(new WheelEvent('wheel', {bubbles:true, deltaY:-400}))
      scroller.scrollTop = 0
    JS
    assert_operator distance_from_bottom, :>, 100
    page.execute_script("document.querySelector('#messages-container').lastElementChild.style.paddingBottom = '350px'")
    assert_operator distance_from_bottom, :>, 100
    assert_equal 30, @room.messages.count
  end
end
