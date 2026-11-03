# Defense-in-depth for standard multipart message uploads.
# File extension and client-reported Content-Type are not sufficient.
# Direct Active Storage signed-id uploads remain intentionally unsupported.
class AttachmentUploadGuard
  SIGNATURES = {
    "image/jpeg" => ->(bytes) { bytes.start_with?("\xFF\xD8\xFF".b) },
    "image/png" => ->(bytes) { bytes.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/webp" => ->(bytes) { bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WEBP" },
    "application/pdf" => ->(bytes) { bytes.start_with?("%PDF-".b) },
    "text/plain" => lambda do |bytes|
      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      utf8.valid_encoding? && !bytes.include?("\x00".b) &&
        !utf8.lstrip.match?(/\A<(?:!doctype\b|html\b|script\b|svg\b|iframe\b|\?xml\b)/i)
    end
  }.freeze

  def self.error_for(raw_uploads)
    return nil if raw_uploads.blank?
    return "Attachments must be uploaded as multipart files" unless raw_uploads.is_a?(Array)

    uploads = raw_uploads.reject(&:blank?)
    return "Too many attachments" if uploads.size > Message::MAX_ATTACHMENTS

    uploads.each do |upload|
      return "Direct uploads are not supported" unless upload.is_a?(ActionDispatch::Http::UploadedFile)
      return "Attachment must not be empty" if upload.size.zero?
      return "Attachment exceeds 5 MB" if upload.size > Message::MAX_ATTACHMENT_BYTES

      advertised_type = upload.content_type.to_s.split(";", 2).first.downcase.strip
      signature_check = SIGNATURES[advertised_type]
      return "Attachment type is not allowed" unless signature_check

      io = upload.tempfile
      begin
        io.rewind
        sample = io.read(4096).to_s.b
        io.rewind
        detected_type = Marcel::MimeType.for(io, name: upload.original_filename.to_s)
        return "Attachment content does not match its declared type" unless
          signature_check.call(sample) && detected_type == advertised_type
      ensure
        io.rewind
      end
    end

    nil
  end
end
