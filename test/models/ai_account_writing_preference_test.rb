require "test_helper"

class AiAccountWritingPreferenceTest < ActiveSupport::TestCase
  test "account writing defaults cannot enable access, spending or auto Send" do
    alice = users(:one)
    preference = AiAccountWritingPreference.create!(user: alice,
      profile_id: "business", writing_style: "professional_client_reply",
      language: "ru", tone: "professional")
    assert preference.valid?
    assert_raises(ActiveRecord::RecordInvalid) do
      AiAccountWritingPreference.create!(user: alice, profile_id: "business",
        writing_style: "professional_client_reply", language: "ru", tone: "professional")
    end
    assert_equal %i[profile_id writing_style language tone], preference.public_snapshot.keys
    assert_not preference.respond_to?(:allow_auto_send)
    assert_not preference.respond_to?(:context_consent)
  end
end
