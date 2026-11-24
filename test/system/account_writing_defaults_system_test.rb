require "application_system_test_case"

class AccountWritingDefaultsSystemTest < ApplicationSystemTestCase
  def login(user)
    # Full-suite Chrome may reuse a session left authenticated by another
    # system scenario. Isolate this account's login before visiting Devise.
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email"
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
    assert_selector ".sd-ai-room-preference-origin", text: "Inherited from account", visible: :all
    assert_equal "ru", find("select[data-ai-draft-target='languageSelect']", visible: :all).value
    assert_equal "professional", find("select[data-ai-draft-target='toneSelect']", visible: :all).value
    assert_selector "button[data-profile-id='business'][aria-pressed='true']"
    assert find("[data-ai-draft-target='resetRoomDefaults']").disabled?

    expand_ai_style(:room)
    within "#ai-room-settings .sd-ai-room-presets" do
      click_button "Friendly"
    end
    assert_selector ".sd-ai-room-preference-origin", text: "Room override", visible: :all, wait: 10
    assert_equal "friendly", AiRoomWritingPreference.find_by!(room: room, user: alice).writing_style
    find("[data-ai-draft-target='resetRoomDefaults']").click
    assert_selector ".sd-ai-room-preference-origin", text: "Inherited from account", visible: :all, wait: 10
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

  test "private group member sees shared defaults, personal override and latest shared reset" do
    owner, member = users(:one), users(:two)
    room = Room.create!(name: "Shared defaults browser acceptance", kind: "private_group",
      is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    room.participants.create!(user: member, group_role: "member")
    shared = { profile_id: "universal", writing_style: "polish_clarity",
      language: "en", tone: "neutral" }
    AiWorkspace::SharedWritingPreferences.write(room: room, actor: owner,
      attributes: shared, expected_revision: 0)

    login(member)
    visit room_path(room, ui_locale: :en)
    fill_in "chat-text", with: "Keep this unsent note intact."
    click_button "Edit unsent message"
    click_button "Room settings"
    assert_selector ".sd-ai-room-preference-origin",
      text: "Inherited from room defaults", visible: :all
    assert_equal "shared", find("[data-ai-draft-preference-source]",
      visible: :all)["data-ai-draft-preference-source"]
    assert_equal "en", find("select[data-ai-draft-target='languageSelect']", visible: :all).value
    assert find("[data-ai-draft-target='resetRoomDefaults']").disabled?

    expand_ai_style(:room)
    within "#ai-room-settings .sd-ai-room-presets" do
      click_button "Friendly"
    end
    assert_selector ".sd-ai-room-preference-origin", text: "Room override", visible: :all, wait: 10
    assert_equal "friendly", AiRoomWritingPreference.find_by!(user: member, room: room).writing_style

    AiWorkspace::SharedWritingPreferences.write(room: room, actor: owner,
      attributes: shared.merge(language: "hy"), expected_revision: 1)
    find("[data-ai-draft-target='resetRoomDefaults']").click
    assert_selector ".sd-ai-room-preference-origin",
      text: "Inherited from room defaults", visible: :all, wait: 10
    assert_equal "hy", find("select[data-ai-draft-target='languageSelect']", visible: :all).value
    assert_nil AiRoomWritingPreference.find_by(room: room, user: member)
    assert_field "chat-text", with: "Keep this unsent note intact."
    assert_equal 0, room.messages.count
    assert_equal 0, AiUsageReservation.count
  end
  test "personal AI settings persist independently and recover from stale revision" do
    alice, bob = users(:one), users(:two)
    login alice
    visit edit_user_registration_path(ui_locale: :en)
    within "#account-personal-ai" do
      assert_text "AI ON"
      click_button "Disable AI"
      assert_text "AI OFF"
      assert_text "Saved"
    end
    assert_equal false, AiPersonalEnablement.find_by!(user: alice).enabled
    assert_nil AiPersonalEnablement.find_by(user: bob)

    visit edit_user_registration_path(ui_locale: :en)
    within "#account-personal-ai" do
      assert_text "AI OFF"
      assert_button "Enable AI", disabled: false
    end
    AiWorkspace::PersonalEnablement.write(actor: alice, enabled: true, expected_revision: 1)
    AiWorkspace::PersonalEnablement.write(actor: alice, enabled: false, expected_revision: 2)
    within "#account-personal-ai" do
      click_button "Enable AI"
      assert_text "Setting changed in another session. Latest value loaded."
      assert_text "AI OFF"
      click_button "Enable AI"
      assert_text "AI ON"
    end
    assert_equal 4, AiPersonalEnablement.find_by!(user: alice).revision
    login bob
    visit edit_user_registration_path(ui_locale: :en)
    within "#account-personal-ai" do
      assert_text "AI ON"
      click_button "Disable AI"
      assert_text "AI OFF"
    end
    assert AiPersonalEnablement.find_by!(user: alice).enabled
    refute AiPersonalEnablement.find_by!(user: bob).enabled
    assert_equal 0, AiUsageReservation.count
  end
  test "private peer indicators update without reloading or changing an unsent draft" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    AiWorkspace::PersonalEnablement.write(actor: bob, enabled: false, expected_revision: 0)
    login alice
    visit room_path(room, ui_locale: :en)
    indicator = "[data-ai-member-user-id='#{bob.id}']"
    assert_selector "#{indicator}[data-ai-member-state='off']", text: "AI OFF", wait: 15
    fill_in "chat-text", with: "Preserve my unsent message."
    AiWorkspace::PersonalEnablement.write(actor: bob, enabled: true, expected_revision: 1)
    page.execute_script("window.dispatchEvent(new Event('focus'))")
    assert_selector "#{indicator}[data-ai-member-state='on']", text: "AI ON", wait: 15
    assert_field "chat-text", with: "Preserve my unsent message."
    assert_nil AiPersonalEnablement.find_by(user: alice)
    assert_equal 0, room.messages.count
    assert_equal 0, AiUsageReservation.count
  end

  test "private group roster shows independent AI preferences and clears removed member status" do
    owner, member = users(:one), users(:two)
    room = Room.create!(name: "AI indicator browser group", kind: "private_group",
      is_private: true, owner: owner)
    room.participants.create!(user: owner, group_role: "owner")
    room.participants.create!(user: member, group_role: "member")
    AiWorkspace::PersonalEnablement.write(actor: member, enabled: false, expected_revision: 0)
    login owner
    visit room_path(room, ui_locale: :en)
    find("#private-group-details > summary").click
    assert_selector "[data-ai-member-user-id='#{owner.id}'][data-ai-member-state='on']", text: "AI ON", wait: 15
    assert_selector "[data-ai-member-user-id='#{member.id}'][data-ai-member-state='off']", text: "AI OFF", wait: 15
    room.participants.where(user: member).delete_all
    page.execute_script("document.dispatchEvent(new Event('room-membership:changed'))")
    assert_no_selector "[data-ai-member-user-id='#{member.id}'][data-ai-member-state='off']", visible: :all, wait: 15
    assert_no_selector "[data-ai-member-user-id='#{member.id}'][data-ai-member-state='on']", visible: :all
    assert_equal 0, AiUsageReservation.count
  end
end
