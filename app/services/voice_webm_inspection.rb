# Verify the actual WebM container and *single Opus audio stream*. The client-
# reported MIME and .webm filename are not trusted. ffprobe is sandboxed to a
# local already-size-limited tempfile with no network protocol and a time cap.
# This is a bounded parser check, not an antivirus scan or transcoding sandbox.
require "json"
require "tempfile"
require "timeout"

class VoiceWebmInspection
  EBML_HEADER = "\x1A\x45\xDF\xA3".b.freeze
  MAX_DURATION_SECONDS = 60.5
  MAX_PROBE_OUTPUT_BYTES = 600_000

  def self.valid?(io)
    io.rewind
    header = io.read(4096).to_s.b
    return false unless header.start_with?(EBML_HEADER)
    return false unless header.include?("webm") && header.include?("A_OPUS")
    return false unless io.respond_to?(:path) && File.file?(io.path)

    Tempfile.create(["voice-inspection", ".json"]) do |result|
      pid = Process.spawn(
        "ffprobe", "-v", "error", "-protocol_whitelist", "file",
        "-show_format", "-show_streams", "-show_packets",
        "-show_entries", "format=format_name,duration:stream=codec_name,codec_type:packet=pts_time,duration_time",
        "-of", "json", "-i", io.path,
        out: result.path, err: File::NULL
      )
      begin
        _, status = Timeout.timeout(6) { Process.waitpid2(pid) }
        return false unless status.success?
      rescue Timeout::Error
        Process.kill("KILL", pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
        return false
      end

      return false if result.size > MAX_PROBE_OUTPUT_BYTES
      metadata = JSON.parse(File.read(result.path))
      streams = metadata.fetch("streams", [])
      return false unless streams.size == 1
      return false unless streams.first["codec_name"] == "opus" &&
        streams.first["codec_type"] == "audio"
      return false unless metadata.dig("format", "format_name").to_s.split(",").include?("webm")

      packets = metadata.fetch("packets", [])
      return false if packets.empty?
      last_second = packets.filter_map do |packet|
        position = Float(packet["pts_time"], exception: false)
        length = Float(packet["duration_time"], exception: false) || 0
        position + length if position
      end.max
      return false unless last_second && last_second.between?(0.08, MAX_DURATION_SECONDS)

      declared = Float(metadata.dig("format", "duration"), exception: false)
      !declared || declared.between?(0.08, MAX_DURATION_SECONDS)
    end
  rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError, IOError, ArgumentError
    false
  ensure
    io.rewind if io && !io.closed?
  end
end
