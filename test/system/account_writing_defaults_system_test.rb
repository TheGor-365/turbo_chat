require "application_system_test_case"

class AccountWritingDefaultsSystemTest < ApplicationSystemTestCase
  def login(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def choose(selector, text)
    find("#{selector} + .sd-ui-select .sd-ui-select__trigger").click
    find("#{selector} + .sd-ui-select .sd-ui-select__option", text: text, visible: true).click
  end

  test "account defaults persist in a new room and explicit room overrides can be reset" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    login(alice)
    visit edit_user_registration_path

    assert_selector "#account-writing-defaults .sd-account-ai-grid", visible: true
    choose "#account-ai-profile", "Business"
    assert_equal "professional_client_reply", find("#account-ai-style", visible: :all).value
    assert_equal "professional", find("#account-ai-tone", visible: :all).value
    choose "#account-ai-language", "Russian"
    assert_equal "ru", find("#account-ai-language", visible: :all).value
    click_button "Save defaults"
    assert_selector "#account-writing-defaults", text: "Account defaults saved", wait: 10
    assert AiAccountWritingPreference.exists?(user: alice, language: "ru",
      writing_style: "professional_client_reply")

    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "A synthetic unsent client request."
    click_button "Edit unsent message"
    click_button "Room settings"
    assert_selector ".sd-ai-room-preference-origin", text: "Inherited from account"
    assert_equal "ru", find("select[data-ai-draft-target='languageSelect']", visible: :all).value
    assert_equal "professional", find("select[data-ai-draft-target='toneSelect']", visible: :all).value
    assert_selector "button[data-profile-id='business'][aria-pressed='true']"
    assert find("[data-ai-draft-target='resetRoomDefaults']").disabled?

    within "#ai-room-settings .sd-ai-room-presets" do
      click_button "Friendly"
    end
    assert_selector ".sd-ai-room-preference-origin", text: "Room override", wait: 10
    assert_equal "friendly", AiRoomWritingPreference.find_by!(room: room, user: alice).writing_style
    find("[data-ai-draft-target='resetRoomDefaults']").click
    assert_selector ".sd-ai-room-preference-origin", text: "Inherited from account", wait: 10
    assert_not AiRoomWritingPreference.exists?(room: room, user: alice)
    assert_field "chat-text", with: "A synthetic unsent client request."
    assert_selector "#ai-room-settings:not([hidden])"
    assert_equal "ru", find("select[data-ai-draft-target='languageSelect']", visible: :all).value
    assert_equal "professional_client_reply",
      AiWorkspace::WritingPreferenceResolver.for(user: alice, room: room).effective.fetch(:writing_style)
    assert_equal 0, room.messages.reload.count
  end

  test "a second account does not inherit someone else's defaults" do
    alice, bob = users(:one), users(:two)
    AiAccountWritingPreference.create!(user: alice,
      profile_id: "business", writing_style: "professional_client_reply",
      language: "ru", tone: "professional")
    login bob
    visit edit_user_registration_path
    assert_equal "auto", find("#account-ai-language", visible: :all).value
    assert_equal "polish_clarity", find("#account-ai-style", visible: :all).value
    assert_selector "#account-writing-defaults", text: "Using system defaults"
    assert_equal 1, AiAccountWritingPreference.count
  end
end
