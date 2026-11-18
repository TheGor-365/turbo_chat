module ThrottledRequests
  extend ActiveSupport::Concern

  private

  def enforce_request_limit(scope:, limit:, period: 60.seconds, identity: nil)
    # IP is derived from ActionDispatch trusted-proxy processing. Never
    # trust a user-provided X-Forwarded-For directly in application code.
    identity ||= current_user&.id ? "user:#{current_user.id}:ip:#{request.remote_ip}" : "ip:#{request.remote_ip}"

    return unless RequestThrottle.exceeded?(scope: scope, identity: identity, limit: limit, period: period)

    response.set_header("Retry-After", period.to_i.to_s)
    response.set_header("Cache-Control", "no-store")
    head :too_many_requests
  end
end
