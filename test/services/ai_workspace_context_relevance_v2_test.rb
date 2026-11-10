require "test_helper"

class AiWorkspaceContextRelevanceV2Test < ActiveSupport::TestCase
  test "unicode term matching works for English, Russian and Armenian" do
    matcher = AiWorkspace::ContextRelevanceV2
    assert_equal ["postgresql", "релиз", "հաշվետվություն"],
      matcher.terms("PostgreSQL релиз հաշվետվություն")
    assert_equal 2, matcher.score("Выпустить PostgreSQL релиз",
      terms: matcher.terms("PostgreSQL релиз"))
    assert_equal 1, matcher.score("Սա հաշվետվություն է",
      terms: matcher.terms("հաշվետվություն PostgreSQL"))
  end

  test "stopwords and long or numeric noise do not dominate ranking" do
    matcher = AiWorkspace::ContextRelevanceV2
    assert_equal ["contract", "audit"], matcher.terms(
      "Please can you review the contract audit 2026?")
    assert_equal 0, matcher.score("Unrelated user feedback",
      terms: matcher.terms("contract audit"))
    assert_operator matcher.terms((1..80).map { |i| "keyword#{i}" }.join(" ")).size,
      :<=, 14
  end

  test "invalid search inputs never become model instructions" do
    matcher = AiWorkspace::ContextRelevanceV2
    assert_equal [], matcher.terms(nil)
    assert_equal [], matcher.terms(123)
    assert_equal 0, matcher.score("No match", terms: [])
  end
end
