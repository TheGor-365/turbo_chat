require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page is public" do
    get root_path
    assert_response :success
  end
end
