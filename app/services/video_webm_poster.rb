# Generates a real still frame from an already stored, validated WebM/VP8 blob.
# Never exposes a public Active Storage URL. Caller must authorize room membership.
require "timeout"
require "tempfile"

class VideoWebmPoster
  MAX_POSTER_BYTES = 1.megabyte
  CACHE_TTL = 12.hours

  def self.for(blob)
    return nil unless blob.content_type == "video/webm" &&
      blob.filename.to_s.downcase.end_with?(".webm") &&
      blob.byte_size <= Message::MAX_ATTACHMENT_BYTES

    Rails.cache.fetch("private-video-poster/v1/#{blob.key}/#{blob.checksum}", expires_in: CACHE_TTL) do
      extract(blob)
    end
  rescue ActiveStorage::FileNotFoundError, IOError, Errno::ENOENT, Errno::EACCES
    nil
  end

  def self.extract(blob)
    blob.open do |video|
      return nil unless VideoWebmInspection.valid?(video)

      Tempfile.create(["chat-poster", ".png"]) do |poster|
        pid = Process.spawn(
          "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
          "-protocol_whitelist", "file", "-threads", "1", "-filter_threads", "1",
          "-i", video.path, "-map", "0:v:0", "-frames:v", "1",
          "-vf", "scale=640:360:force_original_aspect_ratio=decrease",
          "-an", "-f", "image2", "-vcodec", "png",
          "-y", poster.path, out: File::NULL, err: File::NULL
        )
        begin
          _, status = Timeout.timeout(8) { Process.waitpid2(pid) }
          return nil unless status.success?
        rescue Timeout::Error
          Process.kill("KILL", pid) rescue Errno::ESRCH
          Process.waitpid(pid) rescue Errno::ECHILD
          return nil
        end

        return nil unless poster.size.between?(100, MAX_POSTER_BYTES)
        bytes = File.binread(poster.path)
        return nil unless bytes.start_with?("\\x89PNG\\r\\n\\x1A\\n".b)

        bytes
      end
    end
  rescue Errno::ENOENT, Errno::EACCES, IOError
    nil
  end

  private_class_method :extract
end
