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
    assert_selector "form.sd-h4-revision-form textarea[name='deliverable[revision_text]']"
    assert_equal before, Message.count
  end
end
