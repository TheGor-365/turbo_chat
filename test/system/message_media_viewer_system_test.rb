require "application_system_test_case"
require "zlib"

class MessageMediaViewerSystemTest < ApplicationSystemTestCase
  test "private landscape portrait and square images stay inside the bubble and open in an Escape-closeable dialog" do
    room = rooms(:one)
    message = room.messages.build(user: users(:one), body: "Bounded photo gallery")
    [[1800, 400], [400, 1800], [900, 900]].each_with_index do |(width, height), i|
      message.attachments.attach(
        io: StringIO.new(png_bytes(width, height)),
        filename: "shape-#{i}.png", content_type: "image/png"
      )
    end
    message.save!
    sign_in_fixture_user(users(:one))
    visit room_path(room)
    selector = "#message_#{message.id}"
    assert_selector "#{selector} .sd-media-image", count: 3
    assert_no_selector "#{selector} .sd-message-bubble img[src*='/rails/active_storage/']", visible: :all
    original_size = page.driver.browser.manage.window.size

    [[320, 720], [390, 844], [1440, 900]].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      page.execute_script("arguments[0].scrollIntoView({block: 'center'})", find("#{selector} .sd-media-preview", match: :first))
      assert_equal true, page.evaluate_script(<<~JS)
        (() => {
          const bubble = document.querySelector("#{selector} .sd-message-bubble").getBoundingClientRect();
          const images = [...document.querySelectorAll("#{selector} .sd-media-preview")];
          return images.length === 3 && images.every(img => {
            const rect = img.getBoundingClientRect();
            return rect.width <= bubble.width && rect.right <= bubble.right + 1
              && rect.left >= bubble.left - 1 && rect.height <= window.innerHeight * 0.56;
          }) && document.documentElement.scrollWidth <= window.innerWidth;
        })()
      JS
    end

    find("#{selector} .sd-media-image-button", match: :first).click
    assert_selector "#{selector} .sd-media-dialog[open]", visible: true
    assert_selector "#{selector} .sd-media-dialog a[download]", visible: true
    assert_selector "#{selector} .sd-media-dialog img.sd-media-full", visible: true
    assert_equal "Close image viewer", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    page.send_keys(:escape)
    assert_no_selector "#{selector} .sd-media-dialog[open]", visible: :all
    assert_equal "Open image shape-0.png", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end

  private

  def png_bytes(width, height)
    signature = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")
    ihdr = [width, height, 8, 2, 0, 0, 0].pack("NNC5")
    row = ([0, 18, 52, 86].pack("C*") * width)
    row = [0].pack("C") + row.byteslice(0, width * 3)
    data = Zlib::Deflate.deflate(row * height)
    signature + png_chunk("IHDR", ihdr) + png_chunk("IDAT", data) + png_chunk("IEND", "")
  end

  def png_chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end

  def sign_in_fixture_user(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 5
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end
end
