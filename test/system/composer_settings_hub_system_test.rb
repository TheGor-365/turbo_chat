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
    assert_selector ".sd-composer-status-pill[data-composer-setting='spelling'][data-on='On'][data-off='Off']"
    assert_no_selector ".sd-composer-status-pill .translation_missing"
  end

  test "Instructions opens the actual versioned room editor alone and preserves the unsent draft" do
    visit room_path(@room, ui_locale: :en)
    fill_in "chat-text", with: "Keep this draft private and unsent."
    click_button "Instructions"
    assert_selector "#ai-room-settings[open][data-view='instructions']", wait: 10
    assert_selector "#ai-room-settings .sd-room-ai-instructions__fold[open]"
    assert_selector "#ai-room-settings .sd-room-ai-instructions__textarea"
    assert_field "chat-text", with: "Keep this draft private and unsent."
    assert_equal 0, @room.messages.count
    click_button "Close writing settings"
    assert_no_selector "#ai-room-settings[open]", wait: 10
    find(".sd-composer-inspector--room > summary").click
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_selector "#ai-room-settings .sd-ai-room-option--spell"
    assert_equal 0, @room.messages.count
  end

  test "consent tooltip never impersonates the canonical Room settings button" do
    visit room_path(@room, ui_locale: :en)
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
    find(".sd-composer-status-pill[data-composer-setting='consent']").click
    assert_selector "#ai-room-settings[open][data-view='room']", wait: 10
    assert_equal 0, AiRoomContextConsent.where(room: @room, user: @alice).count
    assert_equal 0, @room.messages.count
  end
end
