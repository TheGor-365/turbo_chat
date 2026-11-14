require "test_helper"

class BrandFallbackTest < ActionDispatch::IntegrationTest
  test "public layout explicitly advertises first-party branded icons" do
    get root_path

    assert_response :success
    assert_select 'link[rel="icon"][type="image/x-icon"][href="/favicon.ico?v=h25"]'
    assert_select 'link[rel="icon"][type="image/svg+xml"][href="/favicon.svg?v=h25"]'
    assert_select 'link[rel="apple-touch-icon"][sizes="180x180"][href="/apple-touch-icon.png?v=h25"]'
  end

  test "favicon files contain real SVG, ICO and 180 pixel PNG image data" do
    svg = Rails.public_path.join("favicon.svg").read
    assert_match(/<svg\b/, svg)
    assert_match(/viewBox="0 0 64 64"/, svg)
    assert_match(/M20 11\.5A7\.5/, svg)
    assert_match(/#245bd7/, svg)
    assert_no_match(/<script\b|(?:href|src)=["\']https?:\/\//i, svg)

    ico = Rails.public_path.join("favicon.ico").binread
    assert_operator ico.bytesize, :>, 100
    assert_equal [0, 1, 2], ico.unpack("v3")
    assert_equal [16, 32], [ico.getbyte(6), ico.getbyte(22)]

    %w[apple-touch-icon.png apple-touch-icon-precomposed.png].each do |name|
      png = Rails.public_path.join(name).binread
      assert_operator png.bytesize, :>, 100
      assert_equal "\x89PNG\r\n\x1A\n".b, png.byteslice(0, 8)
      assert_equal [180, 180], png.byteslice(16, 8).unpack("N2")
    end
  end

  test "static error fallbacks are independent of Rails and retain real HTTP statuses" do
    public_exceptions = ActionDispatch::PublicExceptions.new(Rails.public_path.to_s)

    { 404 => "Page not found", 422 => "Your request could not be completed", 500 => "Something went wrong" }.each do |status, title|
      document = Rails.public_path.join("#{status}.html").read
      assert_match(/\A<!DOCTYPE html>/, document)
      assert_includes document, '<html lang="en">'
      assert_includes document, 'name="viewport"'
      assert_includes document, "<h1>#{title}</h1>"
      assert_includes document, 'href="/"'
      assert_includes document, "<style>"
      assert_includes document, '<svg '
      assert_no_match(/<%|<script\b|<link\b|@import|(?:src|href)=["\']https?:\/\/|stack trace|backtrace/i, document)

      env = Rack::MockRequest.env_for("/#{status}", "HTTP_ACCEPT" => "text/html")
      code, headers, body = public_exceptions.call(env)
      assert_equal status, code
      assert_match(/text\/html/i, headers["content-type"])
      assert_includes body.each.to_a.join, "<h1>#{title}</h1>"
    end
  end
end
