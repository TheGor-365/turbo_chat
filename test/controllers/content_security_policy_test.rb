require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "HTML responses enforce a restricted CSP" do
    get root_path
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "Expected enforced Content-Security-Policy header"
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "script-src 'self'"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "frame-ancestors 'none'"
    assert_includes csp, "form-action 'self'"
    assert_includes csp, "connect-src 'self' ws: wss:"
    assert_not_includes csp, "script-src 'self' 'unsafe-inline'"
    assert_not response.headers["Content-Security-Policy-Report-Only"]
  end
end
