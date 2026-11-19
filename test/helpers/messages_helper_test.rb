require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  test "safe headings, emphasis, inline code and source annotations" do
    html = render_message_body("**Brief** [M31]\n- *Rails* + \x60PostgreSQL\x60\n<script>alert(1)</script>")
    fragment = Nokogiri::HTML.fragment(html)
    assert_equal "Brief", fragment.at_css("strong").text
    assert_equal "Rails", fragment.at_css("li em").text
    assert_equal "PostgreSQL", fragment.at_css("li code").text
    assert_equal "[M31]", fragment.at_css(".sd-message-source-ref").text
    assert_empty fragment.css("script, a, img")
    assert_includes fragment.text, "<script>alert(1)</script>"
    assert_includes html, "&lt;script&gt;"
  end

  test "numbered lists and code fences remain inert" do
    html = render_message_body("1. Review\n2. Test\n\n\x60\x60\x60ruby\nputs '<img onerror=bad>'\n\x60\x60\x60")
    fragment = Nokogiri::HTML.fragment(html)
    assert_equal 2, fragment.css("ol li").size
    assert_equal "puts '<img onerror=bad>'", fragment.at_css("pre code").text
    assert_empty fragment.css("img, a, script")
  end

  test "plain chat messages remain readable" do
    fragment = Nokogiri::HTML.fragment(render_message_body("Hello Eric"))
    assert_equal "Hello Eric", fragment.at_css("p").text
    assert_equal 1, fragment.css("p").size
  end
end
