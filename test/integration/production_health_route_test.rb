require "test_helper"

class ProductionHealthRouteTest < ActionDispatch::IntegrationTest
  test "minimal health route is public and returns 200 without signing in" do
    get "/up"
    assert_response :success
    assert_equal "text/html", response.media_type
  end

  test "user-facing root route remains separate from health endpoint" do
    assert_equal "/up", rails_health_check_path
    assert_equal "/", root_path
  end
end
