require "test_helper"
require "tempfile"
require "zlib"

class AttachmentFileIntegrityTest < ActiveSupport::TestCase
  test "accepts an intact one-pixel PNG with valid chunk CRCs" do
    with_upload(tiny_png, filename: "pixel.png", mime: "image/png") do |upload|
      assert_nil AttachmentUploadGuard.error_for([upload])
    end
  end

  test "rejects a truncated PNG with valid magic bytes" do
    with_upload(tiny_png.byteslice(0, 30), filename: "truncated.png", mime: "image/png") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects PNG with wrong chunk CRC despite valid filename and signature" do
    broken = tiny_png.dup
    broken.setbyte(29, broken.getbyte(29) ^ 1)
    with_upload(broken, filename: "bad.png", mime: "image/png") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects PNG dimensions over limit before any image decoding" do
    oversized = png_with_dimensions(8193, 1)
    with_upload(oversized, filename: "oversized.png", mime: "image/png") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "accepts UTF-8 Markdown treated as plain text by the browser" do
    with_upload("# Project notes\n\nNormal **Markdown** content.\n",
      filename: "README.md", mime: "text/plain") do |upload|
      assert_nil AttachmentUploadGuard.error_for([upload])
    end
  end

  test "rejects HTML disguised as a Markdown document" do
    with_upload("<html><script>alert(1)</script></html>",
      filename: "README.md", mime: "text/plain") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects invalid UTF-8 hidden beyond the first 4096 bytes" do
    with_upload(("a" * 5000).b + "\xFF".b, filename: "note.txt", mime: "text/plain") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects NUL hidden beyond the first 4096 bytes" do
    with_upload(("a" * 5000).b + "\x00".b, filename: "note.txt", mime: "text/plain") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects PDF lacking the required EOF marker" do
    with_upload("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n", filename: "missing-eof.pdf", mime: "application/pdf") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  test "rejects WebP with inconsistent RIFF container length" do
    spoof = "RIFF" + [200].pack("V") + "WEBP" + "VP8 " + [4].pack("V") + "abcd"
    with_upload(spoof, filename: "broken.webp", mime: "image/webp") do |upload|
      assert_match(/content does not match/, AttachmentUploadGuard.error_for([upload]))
    end
  end

  private

  def tiny_png
    png_with_dimensions(1, 1)
  end

  def png_with_dimensions(width, height)
    ihdr = [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")
    pixel = [0, 255, 0, 0, 255].pack("C*")
    AttachmentFileIntegrity::PNG_SIGNATURE +
      png_chunk("IHDR", ihdr) +
      png_chunk("IDAT", Zlib::Deflate.deflate(pixel)) +
      png_chunk("IEND", "")
  end

  def png_chunk(type, payload)
    [payload.bytesize].pack("N") + type + payload +
      [Zlib.crc32(type + payload)].pack("N")
  end

  def with_upload(content, filename:, mime:)
    file = Tempfile.new(["attachment-integrity", File.extname(filename)])
    file.binmode
    file.write(content)
    file.rewind

    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: file, filename: filename, type: mime
    )
    yield upload
  ensure
    file&.close!
  end
end
