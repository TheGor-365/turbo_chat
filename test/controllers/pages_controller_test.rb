require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should show public home page" do
    get root_path
    assert_response :success
  end
end
