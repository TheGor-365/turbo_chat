require "application_system_test_case"
require "warden/test/helpers"

class UiErrorModalSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    evidence = @room.messages.create!(user: @bob,
      body: "Synthetic landing request")
    [@alice, @bob].each do |person|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: person).grant!
    end
    item = AiDeliverable.create!(room: @room, owner: @alice,
      kind: "client_brief", state: "draft")
    text = "## Requirements\n- Landing page [M#{evidence.id}]"
    item.revisions.create!(author: @alice, version: 1,
      body_markdown: text, body_sha256: Digest::SHA256.hexdigest(text),
      source_message_ids: [evidence.id])
    Warden.test_mode!
    login_as @alice, scope: :user
  end

  teardown { Warden.test_reset! }

  test "consent revocation opens a modal without replacing saved-documents page" do
    visit room_ai_deliverables_path(@room)
    assert_selector "#h5-saved-documents a[title='Open your saved private document']"
    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!

    find("#h5-saved-documents a[title='Open your saved private document']").click
    assert_selector "dialog.sd-ui-error-dialog[open]", wait: 10
    within "dialog.sd-ui-error-dialog" do
      assert_text "AI access paused"
      click_button "Close and continue"
    end
    assert_no_selector "dialog.sd-ui-error-dialog[open]"
    assert_current_path room_ai_deliverables_path(@room)
    assert_selector "#h5-saved-documents"
  end
  test "hover alone never opens AI permission dialog, actual click opens it" do
    visit room_ai_workspace_path(@room)
    link = find("a[aria-label='Open saved documents']")
    assert_selector "meta[name='turbo-prefetch'][content='false']", visible: false

    AiRoomContextConsent.find_by!(room: @room, user: @bob).revoke!
    link.hover
    # Turbo's default hover-prefetch delay is 100ms. Wait beyond that window
    # to catch the original bug before issuing any click.
    sleep 0.65
    assert_no_selector "dialog.sd-ui-error-dialog[open]"
    assert_current_path room_ai_workspace_path(@room)

    link.click
    assert_selector "dialog.sd-ui-error-dialog[open]", wait: 10
    within "dialog.sd-ui-error-dialog" do
      assert_text "AI access paused"
      click_button "Close and continue"
    end
    assert_current_path room_ai_workspace_path(@room)
    assert_no_selector "dialog.sd-ui-error-dialog[open]"
  end

end
