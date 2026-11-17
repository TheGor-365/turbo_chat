require "application_system_test_case"
require "warden/test/helpers"

# Browser acceptance of the H4 destination using a model-like, synthetic
# brief. The integration test exercises the stubbed generation JSON boundary.
# This system test exercises the actual Signal Deck form and result rendering.
# No provider calls, paid tokens, Send action or database migrations.
class H4MockSemanticReviewSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @alice, @bob = users(:one), users(:two)
    @room = Room.create_private_room([@alice, @bob],
      "private_#{[@alice.id, @bob.id].sort.join('_')}")
    @incoming = @room.messages.create!(user: @bob,
      body: "Checkout returned HTTP 422. Please inspect the Rails validation errors.")
    [@alice, @bob].each do |member|
      AiRoomContextConsent.find_or_initialize_by(room: @room, user: member).grant!
    end
    Warden.test_mode!
    login_as @alice, scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "Save draft uses target-specific CSRF token and stores the current edited text" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    baseline_messages = Message.count

    begin
      visit new_room_ai_deliverable_review_path(@room, demo: "1")
      fill_in "Structured Markdown",
        with: "## Requirements\n- Verify updated checkout [M#{@incoming.id}]"
      click_button "Inspect document"
      assert_selector "button[aria-label='Save private draft']", wait: 10

      # Keep the form editable, but save to the different H5 endpoint.
      fill_in "Structured Markdown",
        with: "## Requirements\n- Verify edited checkout [M#{@incoming.id}]"
      click_button "Save private draft"
      assert_selector "#h5-saved-document", text: "Version 1", wait: 10

      assert_equal "## Requirements\n- Verify edited checkout [M#{@incoming.id}]",
        AiDeliverable.last.latest_revision.body_markdown
      assert_equal baseline_messages, Message.count
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end


  test "room menu opens authorized review in a native dialog without losing an unsent message" do
    message_count = Message.count
    visit room_path(@room)
    fill_in "chat-text", with: "Unsent message stays in room"
    find(".sd-conversation-tools__trigger").click
    within("#conversation-tools-panel") do
      find("a.sd-h4-entry").click
    end

    assert_selector "dialog#sd-review-sheet[open]", wait: 10
    assert_selector "dialog#sd-review-sheet #h4-manual-review", wait: 10
    assert_selector "dialog#sd-review-sheet .sd-h4-stage-nav"
    assert_field "chat-text", with: "Unsent message stays in room"
    assert_equal message_count, Message.count

    within("dialog#sd-review-sheet") do
      fill_in "Structured Markdown",
        with: "## Requirements\\n- Verify updated checkout [M#{@incoming.id}]"
      find("#h4-document-editor .sd-h4-submit").click
    end
    assert_selector "dialog#sd-review-sheet #h4-typed-results .sd-h4-entry", count: 1, wait: 10
    assert_field "chat-text", with: "Unsent message stays in room"
    within("dialog#sd-review-sheet") do
      click_button "Close document review"
    end
    assert_no_selector "dialog#sd-review-sheet[open]"
    assert_selector "dialog#sd-review-sheet .sd-review-sheet__content:empty", visible: :all
    assert_field "chat-text", with: "Unsent message stays in room"
    assert_equal message_count, Message.count
  end

  test "modal Save uses H5 form-action CSRF and does not alter the chat draft" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    before_messages = Message.count

    begin
      visit room_path(@room)
      fill_in "chat-text", with: "Keep my unsent message"
      find(".sd-conversation-tools__trigger").click
      within("#conversation-tools-panel") { find("a.sd-h4-entry").click }
      assert_selector "dialog#sd-review-sheet #h4-document-editor", wait: 10

      within("dialog#sd-review-sheet") do
        fill_in "Structured Markdown",
          with: "## Requirements\\n- Verify edited checkout [M#{@incoming.id}]"
        click_button "Save private draft"
      end
      assert_selector "dialog#sd-review-sheet .sd-review-sheet__saved-link", wait: 10
      assert_selector "dialog#sd-review-sheet .sd-review-sheet__feedback",
        text: /Private draft saved/
      assert_equal "## Requirements\\n- Verify edited checkout [M#{@incoming.id}]",
        AiDeliverable.last.latest_revision.body_markdown
      click_button "Close document review"
      assert_field "chat-text", with: "Keep my unsent message"
      assert_equal before_messages, Message.count
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  test "a mock semantic brief is reviewable in browser, never sent or approved" do
    before = Message.count
    text = [
      "## Objective", "- Diagnose HTTP 422 [M#{@incoming.id}]",
      "## Requirements", "- Inspect Rails validation [M#{@incoming.id}]",
      "## Constraints", "- Constraints: To confirm",
      "## Deliverables", "- Deliverables: To confirm",
      "## Acceptance Criteria", "- Acceptance: To confirm",
      "## Open Questions", "- Deadline and budget: To confirm"
    ].join("\n")

    visit new_room_ai_deliverable_review_path(@room, demo: "1")
    assert_selector "h1", text: "Review a client document"
    fill_in "Structured Markdown", with: text
    find("button[aria-label='Inspect document']").click

    assert_selector "#h4-typed-results .sd-h4-entry", count: 6
    assert_selector "#h4-typed-results .sd-h4-status[data-status='inferred']", count: 2
    assert_selector "#h4-typed-results .sd-h4-status[data-status='needs_confirmation']", count: 4
    assert_selector "#h4-typed-results a[href='#{room_path(@room, focus: @incoming.id)}']", count: 2
    assert_text "Pending manual review"
    assert_selector "form.sd-h4-revision-form textarea[name='deliverable[revision_text]']", visible: :all
    assert_selector "details.sd-h4-advanced:not([open])"
    find("details.sd-h4-advanced > summary").click
    assert_selector "form.sd-h4-revision-form textarea[name='deliverable[revision_text]']", visible: true
    assert_equal before, Message.count
  end
end
