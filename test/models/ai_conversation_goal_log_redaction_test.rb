require "test_helper"

class AiConversationGoalLogRedactionTest < ActiveSupport::TestCase
  test "personal goal and nested text never appear in Rails filtered parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { goal: { purpose: "private reason", constraints: "private boundary",
      desired_outcome: "private expectation", base_revision: 5 } }
    result = filter.filter(params)
    assert_equal "[FILTERED]", result.fetch(:goal)
    assert_not_includes result.inspect, "private reason"
    assert_not_includes result.inspect, "private boundary"
    assert_not_includes result.inspect, "private expectation"
  end
end
