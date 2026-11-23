require "application_system_test_case"

# G1/B19: owner screenshot regressions. Exercise existing canonical actions,
# not a second preference/consent owner and never trigger a provider or Send.
class G1B19OwnerUxSystemTest < ApplicationSystemTestCase
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

  def group
    @group ||= begin
      room = Room.create!(name: "B19 Mobile #{SecureRandom.hex(3)}",
        kind: "private_group", is_private: true, owner: users(:one))
      room.participants.create!(user: users(:one), group_role: "owner")
      room.participants.create!(user: users(:two), group_role: "member")
      room
    end
  end

  test "400px composer reserves second row for AI, full human input and Send; member menu never clips" do
    page.current_window.resize_to(400, 793)
    login_owner
    visit room_path(group, ui_locale: :en)
    fill_in "chat-text", with: "B19 human message stays unsent"

    assert_selector ".sd-g1-workspace-launch .sd-g1-launch-label", visible: true
    assert_selector ".sd-g1-attachments-launch .sd-g1-launch-label", visible: true
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const r = s => document.querySelector(s).getBoundingClientRect()
        const settings = r(".sd-g1-workspace-launch")
        const tools = r(".sd-g1-attachments-launch")
        const ai = r(".sd-adaptive-ai-action")
        const input = r("#chat-text")
        const send = r(".composer-send")
        return {settingsBottom:settings.bottom, toolsBottom:tools.bottom,
          inputTop:input.top, inputWidth:input.width,
          aiTop:ai.top, sendTop:send.top,
          overflow:document.documentElement.scrollWidth}
      })()
    JS
    assert_operator geometry.fetch("settingsBottom"), :<, geometry.fetch("inputTop")
    assert_operator geometry.fetch("toolsBottom"), :<, geometry.fetch("inputTop")
    assert_operator geometry.fetch("inputWidth"), :>=, 190
    assert_in_delta geometry.fetch("aiTop"), geometry.fetch("sendTop"), 12
    assert_operator geometry.fetch("overflow"), :<=, 402

    find("#private-group-details > summary").click
    assert_selector "#private-group-details[open] .sd-private-group-details__popover"
    menu = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector(
          "#private-group-details .sd-private-group-details__popover").getBoundingClientRect()
        return {left:r.left,right:r.right,width:r.width}
      })()
    JS
    assert_operator menu.fetch("left"), :>=, -1
    assert_operator menu.fetch("right"), :<=, 401
    assert_operator menu.fetch("width"), :>=, 260
    assert_equal 0, group.messages.count
    assert_field "chat-text", with: "B19 human message stays unsent"
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "existing instruction title saves on blur in user-local library, no extra revision or Send" do
    room = group
    room.ai_instruction_revisions.create!(editor: users(:one), revision_number: 1,
      content: "Scope and acceptance. No confirmed budget.")
    login_owner
    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "Do not send"
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[data-view='instructions']"

    find(".sd-room-ai-instructions__current > summary").click
    assert_selector ".sd-room-ai-instructions__current-name", text: "Instruction #1"
    find(".sd-room-ai-instructions__current-rename").click
    find(".sd-room-ai-instructions__current-name-input").fill_in with: "Verified technical scope"
    find(".sd-room-ai-instructions__current > summary").click
    assert_selector ".sd-room-ai-instructions__status", text: "Name saved on this device"
    assert_equal 1, room.ai_instruction_revisions.count
    assert_equal 0, room.messages.count

    visit room_path(room, ui_locale: :en)
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='instructions']").click
    find(".sd-room-ai-instructions__current > summary").click
    assert_selector ".sd-room-ai-instructions__current-name", text: "Verified technical scope"
    assert_field "chat-text", with: ""
    assert_equal 1, room.ai_instruction_revisions.count
    assert_equal 0, room.messages.count
  end

  test "Message UI omits duplicate source picker and preserves canonical Context navigation" do
    login_owner
    visit room_path(group, ui_locale: :en)
    fill_in "chat-text", with: "Never Send in settings"
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='message']").click
    assert_selector "#ai-draft-panel[open]"
    assert_no_selector "#ai-draft-panel .sd-ai-source-review", visible: true
    assert_selector "#ai-draft-panel .sd-ai-dialogue-workflows"
    assert_selector "#ai-draft-panel .sd-ai-context-redirect", visible: true
    assert_selector "#ai-draft-panel .sd-h4-composer-link", visible: true
    assert_field "chat-text", with: "Never Send in settings"
    assert_equal 0, group.messages.count
  end
end
