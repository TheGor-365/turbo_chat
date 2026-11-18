# Bounded validation of local WebM video attachments. Only a single VP8
# video track is accepted in v1; audio is intentionally disabled until the
# deferred Linux Mint microphone problem is resolved. No remote protocols.
# This is structural validation, not an AV/malware scanner or sandbox.
require "json"
require "tempfile"
require "timeout"

class VideoWebmInspection
  EBML_HEADER = "\x1A\x45\xDF\xA3".b.freeze
  MAX_DURATION_SECONDS = 10.5
  MAX_WIDTH = 1_280
  MAX_HEIGHT = 720
  MAX_PACKETS = 900
  MAX_REPORT_BYTES = 350_000

  def self.valid?(io)
    io.rewind
    header = io.read(4096).to_s.b
    return false unless header.start_with?(EBML_HEADER)
    return false unless header.include?("webm") && header.include?("V_VP8")
    return false unless io.respond_to?(:path) && File.file?(io.path)

    Tempfile.create(["video-inspection", ".json"]) do |report|
      pid = Process.spawn(
        "ffprobe", "-v", "error", "-protocol_whitelist", "file",
        "-show_format", "-show_streams", "-show_packets",
        "-show_entries", "format=format_name,duration:stream=codec_name,codec_type,width,height:packet=pts_time,duration_time",
        "-of", "json", "-i", io.path, out: report.path, err: File::NULL
      )
      begin
        _, status = Timeout.timeout(6) { Process.waitpid2(pid) }
        return false unless status.success?
      rescue Timeout::Error
        Process.kill("KILL", pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
        return false
      end

      return false if report.size > MAX_REPORT_BYTES
      metadata = JSON.parse(File.read(report.path))
      streams = metadata.fetch("streams", [])
      return false unless streams.size == 1
      stream = streams.first
      return false unless stream["codec_type"] == "video" && stream["codec_name"] == "vp8"
      width = Integer(stream["width"], exception: false)
      height = Integer(stream["height"], exception: false)
      return false unless width && height && width.between?(1, MAX_WIDTH) && height.between?(1, MAX_HEIGHT)
      return false unless metadata.dig("format", "format_name").to_s.split(",").include?("webm")

      packets = metadata.fetch("packets", [])
      return false if packets.empty? || packets.length > MAX_PACKETS
      last_position = packets.filter_map do |packet|
        position = Float(packet["pts_time"], exception: false)
        length = Float(packet["duration_time"], exception: false) || 0
        position + length if position
      end.max
      return false unless last_position && last_position.between?(0.2, MAX_DURATION_SECONDS)

      declared = Float(metadata.dig("format", "duration"), exception: false)
      !declared || declared.between?(0.2, MAX_DURATION_SECONDS)
    end
  rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError, IOError, ArgumentError
    false
  ensure
    io.rewind if io && !io.closed?
  end
end
