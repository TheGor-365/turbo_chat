require "application_system_test_case"
require "warden/test/helpers"

# D3.1a: the status toolbar is a proxy for canonical settings, never a
# second preference store or a paid AI generation action.
class ComposerSettingsHubSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    Warden.test_mode!
    login_as @alice, scope: :user
  end

  teardown { Warden.test_reset! }

  test "all status chips remain visible, reversible spelling toggle uses original controller and never sends" do
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "QA: no chat message must be sent."
    find(".sd-g1-workspace-launch").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector ".sd-composer-status-pill", count: 6
    assert_selector ".sd-composer-status-pill[data-composer-setting='auto'][data-state='locked']"
    assert_selector ".sd-composer-status-pill[data-composer-setting='spelling'][data-state='on']", wait: 10
    find(".sd-composer-status-pill[data-composer-setting='spelling']").click
    assert_selector ".sd-composer-status-pill[data-composer-setting='spelling'][data-state='off']", wait: 10
    assert_equal "false", find("[data-ai-draft-target='spellToggle']", visible: :all)["aria-checked"]
    find(".sd-composer-status-pill[data-composer-setting='spelling']").click
    assert_selector ".sd-composer-status-pill[data-composer-setting='spelling'][data-state='on']", wait: 10
    assert_equal "true", find("[data-ai-draft-target='spellToggle']", visible: :all)["aria-checked"]
    assert_field "chat-text", with: "QA: no chat message must be sent."
    assert_equal 0, @room.messages.count
  end

  test "status on and off labels exist in all locales and remain plain HTML attributes" do
    {
      en: ["On", "Off"],
      ru: ["Вкл", "Выкл"],
      es: ["Sí", "No"],
      hy: ["Միաց.", "Անջ."]
    }.each do |locale, (enabled, disabled)|
      assert_equal enabled, I18n.t("ui.composer_hub.on", locale: locale)
      assert_equal disabled, I18n.t("ui.composer_hub.off", locale: locale)
    end

    visit room_path(@room, ui_locale: :en)
    find(".sd-g1-workspace-launch").click
    assert_selector ".sd-composer-status-pill[data-composer-setting='spelling'][data-on='On'][data-off='Off']"
    assert_no_selector ".sd-composer-status-pill .translation_missing"
  end

  test "Instructions opens the actual versioned room editor alone and preserves the unsent draft" do
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "Keep this draft private and unsent."
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='instructions']").click
    assert_selector "#ai-room-settings[open][data-view='instructions']", wait: 10
    assert_selector "#ai-room-settings .sd-room-ai-instructions__fold[open]"
    assert_selector "#ai-room-settings .sd-room-ai-instructions__textarea"
    assert_field "chat-text", with: "Keep this draft private and unsent."
    assert_equal 0, @room.messages.count
    click_button "Close writing settings"
    assert_no_selector "#ai-room-settings[open]", wait: 10
    find(".sd-g1-workspace-launch").click
    find("#sd-mobile-workspace [data-workspace-tab='room']").click
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_selector "#ai-room-settings .sd-ai-room-option--spell"
    assert_equal 0, @room.messages.count
  end

  test "one composer launcher replaces duplicate Status and AI settings rows" do
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "Single-entry QA — do not send."
    assert_selector ".sd-g1-workspace-launch", visible: true
    assert_no_selector ".message-composer > .sd-composer-inspectors--unified", visible: true
    assert_no_selector ".sd-mobile-composer-toolbar", visible: true

    find(".sd-g1-workspace-launch").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']"
    assert_selector "#sd-mobile-workspace .sd-composer-status-pill", count: 6
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='status'][aria-current='page']"
    assert_selector "#sd-mobile-workspace .sd-workspace-tabs [data-workspace-tab='room']", visible: true
    find("#sd-mobile-workspace [data-workspace-tab='plan']").click
    assert_selector "#sd-ai-effective-plan:not([hidden])", wait: 10
    find("#sd-ai-effective-plan [data-workspace-tab='status']").click
    assert_selector "#sd-mobile-workspace[open][data-mode='status']", wait: 10
    find("#sd-mobile-workspace .sd-mobile-workspace__close").click
    assert_no_selector "#sd-mobile-workspace[open]"
    assert_field "chat-text", with: "Single-entry QA — do not send."
    assert_equal 0, @room.messages.count
  end

  test "consent tooltip never impersonates the canonical Room settings button" do
    visit room_path(@room, ui_locale: :en)
    find(".sd-g1-workspace-launch").click
    assert_selector ".sd-composer-status-pill[data-composer-setting='consent'][title*='permission']", wait: 10
    assert_no_selector ".sd-composer-status-pill[title*='Room settings']"
    fill_in "chat-text", with: "Keep this draft unsent"
    click_button "Edit unsent message"
    click_button "Room settings"
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_field "chat-text", with: "Keep this draft unsent"
    assert_equal 0, @room.messages.count
  end

  test "consent badge never directly grants AI history" do
    visit room_path(@room, ui_locale: :en)
    assert_equal 0, AiRoomContextConsent.where(room: @room, user: @alice).count
    find(".sd-g1-workspace-launch").click
    find(".sd-composer-status-pill[data-composer-setting='consent']").click
    assert_selector "dialog.sd-consent-explain-dialog[open]", text: "AI history permissions", wait: 10
    assert_selector "dialog.sd-consent-explain-dialog", text: @bob.chat_label
    assert_equal 0, AiRoomContextConsent.where(room: @room, user: @alice).count
    assert_equal 0, @room.messages.count
    within "dialog.sd-consent-explain-dialog" do
      click_button "Allow AI to use my messages"
    end
    assert_selector "dialog.sd-consent-explain-dialog", text: "Allowed", wait: 10
    assert_equal 1, AiRoomContextConsent.where(room: @room, user: @alice)
      .where.not(granted_at: nil).count
    assert_equal 0, AiRoomContextConsent.where(room: @room, user: @bob)
      .where.not(granted_at: nil).count
    assert_equal 0, @room.messages.count
  end

  test "missing consent request prepares a draft but never sends it automatically" do
    visit room_path(@room, ui_locale: :en)
    find(".sd-g1-workspace-launch").click
    find(".sd-composer-status-pill[data-composer-setting='contextReady']").click
    assert_selector "dialog.sd-consent-explain-dialog[open]", wait: 10
    within "dialog.sd-consent-explain-dialog" do
      click_button "Prepare request in chat"
    end
    assert_no_selector "dialog.sd-consent-explain-dialog[open]"
    assert_field "chat-text", with: /Please review AI history access/
    assert_equal 0, @room.messages.count
    assert_equal 0, AiRoomContextConsent.where(room: @room).count
  end
end
