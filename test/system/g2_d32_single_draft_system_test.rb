require "application_system_test_case"

# G2/D3.2: one unsent message; the quick three and expanded six presets
# share the canonical ai-draft controller. Preview/apply/undo are human-only
# operations, distinct from provider invocation and explicit Send.
class G2D32SingleDraftSystemTest < ApplicationSystemTestCase
  def sign_in
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def room
    @room ||= Room.create_private_room([users(:one), users(:two)],
      "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
  end

  def open_message
    if page.evaluate_script("window.innerWidth") <= 620
      find(".sd-g1-workspace-launch").click
      find("#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='message']").click
    else
      click_button "Edit unsent message"
    end
    assert_selector "#ai-draft-panel[open]"
  end

  test "three fast styles and six expanded presets reflect one selection without sending" do
    sign_in
    visit room_path(room, ui_locale: :en)
    original = "Please inspect the Rails 422 response before quoting a price."
    fill_in "chat-text", with: original
    open_message

    assert_selector "#ai-draft-panel .sd-ai-style-shortcuts button", count: 3, visible: true
    assert_selector "#ai-draft-panel .sd-ai-style-details:not([open])"
    find("#ai-draft-panel .sd-ai-style-shortcuts button[data-preset-id='friendly']").click
    assert_selector "#ai-draft-panel .sd-ai-style-shortcuts button[data-preset-id='friendly'][aria-pressed='true']"
    assert_selector "#ai-draft-panel summary.sd-ai-style-summary", text: "Friendly"
    assert_field "chat-text", with: original

    find("#ai-draft-panel summary.sd-ai-style-summary").click
    assert_selector "#ai-draft-panel .sd-ai-draft-presets button", count: 6, visible: true
    assert_selector "#ai-draft-panel .sd-ai-draft-presets button[data-preset-id='friendly'][aria-pressed='true']"
    assert_no_selector "#ai-draft-panel .sd-ai-style-shortcuts", visible: true

    find("#ai-draft-panel .sd-ai-draft-presets button[data-preset-id='concise']").click
    assert_selector "#ai-draft-panel summary.sd-ai-style-summary", text: "Concise"
    find("#ai-draft-panel summary.sd-ai-style-summary").click
    assert_selector "#ai-draft-panel .sd-ai-style-shortcuts button", count: 3, visible: true
    assert_field "chat-text", with: original
    assert_equal 0, room.messages.count
  end

  test "human local Preview Apply Undo never sends or incurs model request" do
    sign_in
    visit room_path(room, ui_locale: :en)
    original = "Please inspect the Rails 422 error."
    edited = "Please inspect the Rails 422 validation error before proposing a fix."
    fill_in "chat-text", with: original
    open_message
    assert_field "Editable working copy", with: original

    fill_in "Editable working copy", with: edited
    assert_field "chat-text", with: original
    find("#ai-draft-panel [data-ai-draft-target='previewDraftButton']").click
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview[open]"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview__body", text: edited
    assert_equal 0, room.messages.count

    click_button "Apply to message"
    assert_field "chat-text", with: edited
    assert_equal 0, room.messages.count
    click_button "Undo applied edit"
    assert_field "chat-text", with: original
    assert_equal 0, room.messages.count
  end

  test "owner polishing preserves one accessible working heading and three-column action geometry" do
    page.current_window.resize_to(1440, 900)
    AiWorkspace::ContextReplyGeneration.stub(:enabled?, true) do
      AiWorkspace::ContextTaskGeneration.stub(:enabled?, true) do
        sign_in
        visit room_path(room, ui_locale: :en)
        fill_in "chat-text", with: "Keep this human draft"
        open_message

        assert_selector "#ai-draft-panel .sd-ai-ui-section--working .sd-ai-ui-heading h4", count: 1
        assert_no_selector "#ai-draft-panel .sd-ai-ui-section--working .sd-ai-ui-heading p", visible: true
        assert_selector "#ai-draft-panel label[for='ai-draft-edit'].sd-visually-hidden", visible: :all
        assert_field "Editable working copy", with: "Keep this human draft"

        metrics = page.evaluate_script(<<~JS)
          (() => {
            const sheet = document.querySelector("#ai-draft-panel")
            const actions = sheet.querySelector(".sd-ai-ui-section--actions .sd-ai-ui-action-grid")
            const custom = actions.querySelector(".sd-ai-custom-instructions")
            const dialogue = sheet.querySelector(".sd-ai-dialogue-workflows__actions")
            const visible = Array.from(dialogue.children).filter(
              el => getComputedStyle(el).display !== "none")
            const style = sheet.querySelector(".sd-ai-style-summary")
            const cols = el => getComputedStyle(el).gridTemplateColumns.trim().split(/\\s+/).length
            return {actionColumns: cols(actions), customWidth: custom.getBoundingClientRect().width,
              gridWidth: actions.getBoundingClientRect().width,
              dialogueColumns: cols(dialogue), dialogueWidths: visible.map(
                el => el.getBoundingClientRect().width),
              styleList: getComputedStyle(style).listStyleType}
          })()
        JS
        assert_equal 3, metrics.fetch("actionColumns"), metrics.inspect
        assert_in_delta metrics.fetch("gridWidth"), metrics.fetch("customWidth"), 2
        assert_equal 3, metrics.fetch("dialogueColumns"), metrics.inspect
        assert_equal 3, metrics.fetch("dialogueWidths").length, metrics.inspect
        assert_operator metrics.fetch("dialogueWidths").max - metrics.fetch("dialogueWidths").min, :<=, 2
        assert_equal "none", metrics.fetch("styleList")
        assert_equal 0, room.messages.count
      end
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "three room setting switch cards stretch to the same row height" do
    page.current_window.resize_to(1440, 900)
    sign_in
    visit room_path(room, ui_locale: :en)
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='room']").click
    assert_selector "#ai-room-settings .sd-ai-room-group--options > .sd-ai-room-option", count: 3

    heights = page.evaluate_script(<<~JS)
      (() => Array.from(document.querySelectorAll(
        "#ai-room-settings .sd-ai-room-group--options > .sd-ai-room-option"
      )).map(el => el.getBoundingClientRect().height))()
    JS
    assert_equal 3, heights.length
    assert_operator heights.min, :>=, 100
    assert_operator heights.max - heights.min, :<=, 2, heights.inspect
    assert_equal 0, room.messages.count
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
