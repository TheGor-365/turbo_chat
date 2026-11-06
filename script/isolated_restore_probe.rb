# frozen_string_literal: true

# Run only against a restored, disposable PostgreSQL instance.
# This probes real Rails routes without knowing or changing the source users' passwords.
require "warden/test/helpers"
require "securerandom"

abort "Refusing to run outside the isolated recovery environment" unless
  ENV["TURBO_CHAT_ISOLATED_RECOVERY"] == "1" &&
  ENV.fetch("PGHOST", "").start_with?("tc-restore-app-db-")

class IsolatedRestoreProbe
  include Warden::Test::Helpers

  def run!
    rooms = Room.where(is_private: true).includes(participants: :user)
    room = rooms.find do |candidate|
      candidate.participants.map(&:user).uniq.length == 2 &&
        candidate.messages.exists?
    end
    abort "No populated two-person private conversation to inspect" unless room

    members = room.participants.map(&:user).uniq
    attachment = ActiveStorage::Attachment
      .where(record_type: "Message", record_id: room.messages.select(:id))
      .includes(:blob).find { |item| Message::ALLOWED_CONTENT_TYPES.include?(item.blob.content_type) }
    abort "No permissible private attachment in backed-up conversation" unless attachment

    anonymous = new_session
    anonymous.get("/rooms/#{room.id}")
    expect_status!(anonymous, 302, "guest private room")
    anonymous.get("/chat-attachments/#{attachment.id}")
    expect_status!(anonymous, 302, "guest private attachment")

    members.each do |member|
      session = authenticated_session(member)
      session.get("/rooms/#{room.id}")
      expect_status!(session, 200, "private room for participant")

      if attachment.blob.content_type.in?(%w[video/webm audio/webm])
        session.get("/chat-attachments/#{attachment.id}", headers: { "Range" => "bytes=0-99" })
        expect_status!(session, 206, "private media range for participant")
      else
        session.get("/chat-attachments/#{attachment.id}")
        expect_status!(session, 200, "private attachment for participant")
      end
      abort "Private attachment unexpectedly empty" if session.response.body.empty?

      if attachment.blob.content_type == "video/webm"
        session.get("/chat-attachments/#{attachment.id}/poster")
        expect_status!(session, 200, "private video poster for participant")
        abort "Invalid PNG video poster" unless session.response.body.b.start_with?("\x89PNG\r\n\x1A\n".b)
      end
    end

    # A temporary stranger exists ONLY within this disposable restored database.
    # It cannot access the source app or its production credentials.
    stranger = User.create!(
      email: "isolated-restore-#{SecureRandom.hex(8)}@example.test",
      password: SecureRandom.hex(24)
    )
    outsider = authenticated_session(stranger)
    outsider.get("/rooms/#{room.id}")
    expect_status!(outsider, 403, "private room for unrelated account")
    outsider.get("/chat-attachments/#{attachment.id}")
    expect_status!(outsider, 404, "private attachment for unrelated account")
    if attachment.blob.content_type == "video/webm"
      outsider.get("/chat-attachments/#{attachment.id}/poster")
      expect_status!(outsider, 404, "private video poster for unrelated account")
    end

    puts "PASS: isolated Rails boot, two-member room authorization, private media and stranger denial."
    puts "Inspected restored room, two original users and one attachment; no private content printed."
  ensure
    Warden.test_reset!
  end

  private

  def new_session
    ActionDispatch::Integration::Session.new(Rails.application).tap { |session| session.host! "localhost" }
  end

  def authenticated_session(user)
    Warden.test_reset!
    login_as(user, scope: :user)
    new_session
  end

  def expect_status!(session, expected, context)
    actual = session.response.status
    abort "FAIL: #{context}: HTTP #{actual}, expected #{expected}" unless actual == expected
  end
end

IsolatedRestoreProbe.new.run!
