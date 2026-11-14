# Defense-in-depth for standard multipart message uploads.
# File extension and client-reported Content-Type are not sufficient.
# Direct Active Storage signed-id uploads remain intentionally unsupported.
class AttachmentUploadGuard
  SIGNATURES = {
    "image/jpeg" => ->(bytes) { bytes.start_with?("\xFF\xD8\xFF".b) },
    "image/png" => ->(bytes) { bytes.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/webp" => ->(bytes) { bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WEBP" },
    "application/pdf" => ->(bytes) { bytes.start_with?("%PDF-".b) },
    "audio/webm" => ->(bytes) { bytes.start_with?(VoiceWebmInspection::EBML_HEADER) },
    "video/webm" => ->(bytes) { bytes.start_with?(VideoWebmInspection::EBML_HEADER) },
    "text/plain" => lambda do |bytes|
      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      utf8.valid_encoding? && !bytes.include?("\x00".b) &&
        !utf8.lstrip.match?(/\A<(?:!doctype\b|html\b|script\b|svg\b|iframe\b|\?xml\b)/i)
    end
  }.freeze

  # Markdown remains inert UTF-8 text; Marcel may classify it as plain
  # or Markdown text depending on its filename and OS MIME database.
  TEXT_CONTENT_TYPES = %w[text/plain text/markdown].freeze

  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  def self.error_for(raw_uploads)
    return nil if raw_uploads.blank?
    return I18n.t("ui.upload.multipart_required") unless raw_uploads.is_a?(Array)

    uploads = raw_uploads.reject(&:blank?)
    return I18n.t("ui.upload.too_many") if uploads.size > Message::MAX_ATTACHMENTS

    uploads.each do |upload|
      error = check_file(upload, allowed_types: SIGNATURES.keys,
                        max_bytes: Message::MAX_ATTACHMENT_BYTES, label: :attachment)
      if error
        # Name the first rejected file when several were selected. Never
        # include file contents or a client-supplied path in the error.
        filename = File.basename(upload.original_filename.to_s.tr("\\", "/"))
          .gsub(/[[:cntrl:]]/, "").slice(0, 80) if upload.respond_to?(:original_filename)
        return filename.present? ? "#{error} (#{filename})" : error
      end
    end

    nil
  end

  # Called before Devise may persist an avatar or attach an existing blob.
  # A signed Active Storage blob ID is not a validated multipart upload.
  def self.avatar_error_for(raw_upload)
    return nil if raw_upload.blank?

    check_file(raw_upload, allowed_types: AVATAR_CONTENT_TYPES,
               max_bytes: 5.megabytes, label: :avatar)
  end

  def self.check_file(upload, allowed_types:, max_bytes:, label:)
    return I18n.t("ui.upload.direct_not_supported") unless upload.is_a?(ActionDispatch::Http::UploadedFile)
    return I18n.t("ui.upload.empty", label: I18n.t("ui.upload.labels.#{label}")) if upload.size.zero?
    return I18n.t("ui.upload.exceeds_limit", label: I18n.t("ui.upload.labels.#{label}")) if upload.size > max_bytes

    advertised_type = upload.content_type.to_s.split(";", 2).first.downcase.strip
    return I18n.t("ui.upload.type_not_allowed", label: I18n.t("ui.upload.labels.#{label}")) unless allowed_types.include?(advertised_type)

    signature_check = SIGNATURES.fetch(advertised_type)
    io = upload.tempfile
    begin
      io.rewind
      sample = io.read(4096).to_s.b
      io.rewind
      detected_type = Marcel::MimeType.for(io, name: upload.original_filename.to_s)
      markdown_text = advertised_type == "text/plain" &&
        upload.original_filename.to_s.match?(/\.(?:md|markdown)\z/i) &&
        TEXT_CONTENT_TYPES.include?(detected_type)
      verified_voice = advertised_type == "audio/webm" &&
        upload.original_filename.to_s.downcase.end_with?(".webm") &&
        %w[audio/webm video/webm].include?(detected_type)
      verified_video = advertised_type == "video/webm" &&
        upload.original_filename.to_s.downcase.end_with?(".webm") &&
        %w[audio/webm video/webm].include?(detected_type)
      mime_matches = detected_type == advertised_type || markdown_text || verified_voice || verified_video
      return I18n.t("ui.upload.content_mismatch", label: I18n.t("ui.upload.labels.#{label}")) unless
        signature_check.call(sample) && mime_matches &&
        AttachmentFileIntegrity.valid?(io, advertised_type)
    ensure
      io.rewind
    end

    nil
  end
  private_class_method :check_file
end
