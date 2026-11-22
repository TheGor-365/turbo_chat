require "application_system_test_case"

# G1/B18: the one visible composer launcher navigates the existing six
# canonical task screens. It never sends or grants AI consent by itself.
class G1B18ComposerRoomHierarchySystemTest < ApplicationSystemTestCase
  def login_owner
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def private_group
    @private_group ||= begin
      room = Room.create!(name: "B18 Review #{SecureRandom.hex(3)}",
        kind: "private_group", is_private: true, owner: users(:one))
      room.participants.create!(user: users(:one), group_role: "owner")
      room.participants.create!(user: users(:two), group_role: "member")
      room
    end
  end

  test "desktop AI workspace opens at input width without duplicate control strips" do
    page.current_window.resize_to(1440, 900)
    login_owner
    visit room_path(private_group, ui_locale: :en)
    fill_in "chat-text", with: "B18 do not Send"

    assert_selector ".composer-controls .sd-g1-workspace-launch", visible: true
    assert_no_selector ".message-composer > .sd-composer-inspectors--unified", visible: true
    assert_no_selector ".sd-mobile-composer-toolbar", visible: true

    find(".sd-g1-workspace-launch").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='status'][aria-current='page']"
    assert_selector "#sd-mobile-workspace .sd-composer-status-pill", count: 6
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const sheet = document.querySelector("#sd-mobile-workspace").getBoundingClientRect()
        const room = document.querySelector("#room_container").getBoundingClientRect()
        const input = document.querySelector("#chat-text").getBoundingClientRect()
        return {sheetLeft:sheet.left, sheetRight:sheet.right,
          roomLeft:room.left, roomRight:room.right, sheetBottom:sheet.bottom,
          inputTop:input.top}
      })()
    JS
    assert_operator geometry.fetch("sheetLeft"), :>=, geometry.fetch("roomLeft") - 2
    assert_operator geometry.fetch("sheetRight"), :<=, geometry.fetch("roomRight") + 2
    assert_operator geometry.fetch("sheetBottom"), :<=, geometry.fetch("inputTop") + 4

    find("#sd-mobile-workspace [data-workspace-tab='room']").click
    assert_selector "#ai-room-settings[open][data-view='room']"
    assert_no_selector "#ai-room-settings .sd-ai-room-context", visible: :all
    find("#ai-room-settings [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open]"
    assert_no_selector "#ai-draft-panel .sd-ai-draft-context", visible: :all
    assert_field "chat-text", with: "B18 do not Send"
    assert_equal 0, private_group.messages.count
    assert_equal 0, AiUsageReservation.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "400px mobile shares one input-anchored navigation and preserves human Send" do
    page.current_window.resize_to(400, 793)
    login_owner
    visit room_path(private_group, ui_locale: :en)
    fill_in "chat-text", with: "Mobile B18 not sent"
    assert_selector ".sd-g1-workspace-launch", visible: true
    assert_selector ".sd-g1-attachments-launch", visible: true
    assert_no_selector ".sd-mobile-composer-toolbar", visible: true
    find(".sd-g1-workspace-launch").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const status = document.querySelector("#sd-mobile-workspace").getBoundingClientRect()
        const input = document.querySelector("#chat-text").getBoundingClientRect()
        return {width:status.width, left:status.left, right:status.right,
          sheetBottom:status.bottom, inputTop:input.top,
          scrollWidth:document.documentElement.scrollWidth}
      })()
    JS
    assert_in_delta 400, metrics.fetch("width"), 3
    assert_in_delta 0, metrics.fetch("left"), 2
    assert_operator metrics.fetch("right"), :<=, 402
    assert_operator metrics.fetch("sheetBottom"), :<=, metrics.fetch("inputTop") + 4
    assert_operator metrics.fetch("scrollWidth"), :<=, 402

    find("#sd-mobile-workspace [data-workspace-tab='context']").click
    assert_selector "#sd-ai-context-studio[open]", wait: 10
    find("#sd-ai-context-studio [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[open][data-view='instructions']", wait: 10
    find("#ai-room-settings [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open]", wait: 10
    find("#ai-draft-panel [data-workspace-tab='status']").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']", wait: 10
    find("#sd-mobile-workspace .sd-mobile-workspace__close").click
    assert_field "chat-text", with: "Mobile B18 not sent"
    assert_equal 0, private_group.messages.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "private group identity lives in header menu while room/message sheets stay task-only" do
    login_owner
    room = private_group
    visit room_path(room, ui_locale: :en)
    within("#private-group-details") do
      find("summary").click
      assert_selector ".sd-private-group-details__identity-copy", text: room.name
      assert_selector ".sd-private-group-details__meta", text: /owner/i
      assert_selector ".sd-private-group-details__meta", text: users(:one).chat_label
      assert_selector ".sd-private-group-details__meta", text: "Members"
      assert_selector ".sd-private-group-details__trigger-icon svg"
      assert_selector ".sd-private-group-details__popover", visible: true
    end
    find("#private-group-details > summary").click
    assert_selector "#private-group-details:not([open])"
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='room']").click
    assert_no_selector "#ai-room-settings .sd-ai-room-context", visible: :all
    assert_selector "#ai-room-settings .sd-room-settings-content"
    find("#ai-room-settings [data-workspace-tab='message']").click
    assert_no_selector "#ai-draft-panel .sd-ai-draft-context", visible: :all
    assert_equal 0, room.messages.count
  end
end
