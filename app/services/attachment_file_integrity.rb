# Additional bounded, structural checks after MIME/signature inspection.
# All uploads are size-limited to 5 MB *before* this verifier reads them.
# These checks detect truncated/spoofed containers, NOT malware or all
# decoder bugs. Production still needs a well-maintained image decoder.
require "zlib"

class AttachmentFileIntegrity
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
  MAX_IMAGE_SIDE = 8_192
  MAX_PIXELS = 16_000_000
  MAX_PNG_CHUNKS = 10_000

  def self.valid?(io, content_type)
    io.rewind
    bytes = io.read.to_s.b

    case content_type
    when "image/jpeg"
      valid_jpeg?(bytes)
    when "image/png"
      valid_png?(bytes)
    when "image/webp"
      valid_webp?(bytes)
    when "application/pdf"
      valid_pdf_envelope?(bytes)
    when "text/plain"
      valid_plain_text?(bytes)
    else
      false
    end
  rescue IOError, ArgumentError, Zlib::Error
    false
  ensure
    io.rewind
  end

  def self.valid_plain_text?(bytes)
    utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
    utf8.valid_encoding? && !bytes.include?("\x00".b) &&
      !utf8.lstrip.match?(/\A<(?:!doctype\b|html\b|script\b|svg\b|iframe\b|\\?xml\b)/i)
  end
  private_class_method :valid_plain_text?

  def self.valid_jpeg?(bytes)
    return false unless bytes.start_with?("\xFF\xD8\xFF".b)

    # Detect absent end-of-image on obviously truncated JPEG files.
    eoi = bytes.rindex("\xFF\xD9".b)
    eoi && (bytes.bytesize - eoi - 2) <= 128
  end
  private_class_method :valid_jpeg?

  def self.valid_webp?(bytes)
    return false if bytes.bytesize < 20
    return false unless bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
    return false unless bytes.byteslice(4, 4).unpack1("V") == bytes.bytesize - 8
    return false unless %w[VP8\  VP8L VP8X].include?(bytes.byteslice(12, 4))

    first_chunk_size = bytes.byteslice(16, 4).unpack1("V")
    first_chunk_size.positive? && first_chunk_size <= bytes.bytesize - 20
  end
  private_class_method :valid_webp?

  def self.valid_pdf_envelope?(bytes)
    return false unless bytes.match?(/\A%PDF-(?:1\.[0-7]|2\.0)\b/)

    # PDF can use incremental updates. An EOF marker must be near the end.
    tail = bytes.byteslice(-2048, 2048) || bytes
    eof_position = tail.rindex("%%EOF")
    return false unless eof_position

    tail.byteslice(eof_position + 5..).to_s.strip.empty?
  end
  private_class_method :valid_pdf_envelope?

  def self.valid_png?(bytes)
    return false unless bytes.start_with?(PNG_SIGNATURE)

    offset = PNG_SIGNATURE.bytesize
    chunk_index = 0
    seen_idat = false

    while offset + 12 <= bytes.bytesize && chunk_index < MAX_PNG_CHUNKS
      length = bytes.byteslice(offset, 4).unpack1("N")
      return false if length > bytes.bytesize - offset - 12

      type = bytes.byteslice(offset + 4, 4)
      payload = bytes.byteslice(offset + 8, length)
      crc = bytes.byteslice(offset + 8 + length, 4).unpack1("N")
      return false unless Zlib.crc32(type + payload) == crc

      if chunk_index.zero?
        return false unless type == "IHDR" && length == 13
        width, height = payload.unpack("NN")
        return false if width.zero? || height.zero?
        return false if width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE
        return false if width * height > MAX_PIXELS
      end

      seen_idat = true if type == "IDAT" && length.positive?
      offset += 12 + length
      return seen_idat && length.zero? && offset == bytes.bytesize if type == "IEND"

      chunk_index += 1
    end

    false
  end
  private_class_method :valid_png?
end
