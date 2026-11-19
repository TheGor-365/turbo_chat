# frozen_string_literal: true
require "test_helper"
require "yaml"
require "tempfile"

class LocalizedUploadGuardTest < ActiveSupport::TestCase
  LOCALES = %w[en ru hy es].freeze

  test "guard rejects unsupported multipart representation without changing permitted file types" do
    LOCALES.each do |locale|
      I18n.with_locale(locale) do
        assert_equal I18n.t("ui.upload.multipart_required"),
          AttachmentUploadGuard.error_for("malformed-attachment-parameter")
        assert_equal I18n.t("ui.upload.direct_not_supported"),
          AttachmentUploadGuard.avatar_error_for("signed-blob-id")
        assert_equal I18n.t("ui.upload.too_many"),
          AttachmentUploadGuard.error_for(Array.new(Message::MAX_ATTACHMENTS + 1, "excess"))
        assert_nil AttachmentUploadGuard.avatar_error_for(nil)
        assert_nil AttachmentUploadGuard.error_for(nil)
      end
    end
  end

  test "the same empty and forbidden MIME uploads produce localized errors in four languages" do
    Tempfile.create(["localized-upload", ".txt"]) do |file|
      file.binmode
      file.flush
      upload = ActionDispatch::Http::UploadedFile.new(
        tempfile: file, filename: "sample.txt", type: "text/plain"
      )
      LOCALES.each do |locale|
        I18n.with_locale(locale) do
          assert_equal I18n.t("ui.upload.empty", label: I18n.t("ui.upload.labels.avatar")),
            AttachmentUploadGuard.avatar_error_for(upload)
          assert_equal I18n.t("ui.upload.empty", label: I18n.t("ui.upload.labels.attachment")) + " (sample.txt)",
            AttachmentUploadGuard.error_for([upload])
        end
      end

      file.write("x")
      file.flush
      LOCALES.each do |locale|
        I18n.with_locale(locale) do
          assert_equal I18n.t("ui.upload.type_not_allowed", label: I18n.t("ui.upload.labels.avatar")),
            AttachmentUploadGuard.avatar_error_for(upload)
        end
      end
    end
  end

  test "spoofed upload rejects its body and sanitizes the visible file label" do
    Tempfile.create(["localized-spoof", ".png"]) do |file|
      file.binmode
      file.write("<html>spoof</html>")
      file.flush
      upload = ActionDispatch::Http::UploadedFile.new(
        tempfile: file, filename: "../spoof.png", type: "image/png"
      )
      LOCALES.each do |locale|
        I18n.with_locale(locale) do
          msg = AttachmentUploadGuard.error_for([upload])
          expected = I18n.t("ui.upload.content_mismatch",
            label: I18n.t("ui.upload.labels.attachment"))
          assert_equal "#{expected} (spoof.png)", msg
          refute_includes msg, "<html>"
          refute_includes msg, "../"
        end
      end
    end
  end
end
