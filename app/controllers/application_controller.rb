class ApplicationController < ActionController::Base
  include Pagy::Backend
  include ThrottledRequests
  around_action :with_interface_locale
  before_action :turbo_frame_request_variant

  # Empty HTML error responses otherwise become a browser-generated error page.
  # Convert only supported user-facing formats. JSON, Turbo Stream, XHR and
  # private media must remain machine-readable with their original status.
  def head(status, options = nil)
    code = Rack::Utils.status_code(status)
    return super unless UiErrorState::SUPPORTED_STATUSES.include?(code) && ui_error_html_request?
    render_ui_error(code)
  end

  rescue_from ActiveRecord::RecordNotFound, with: :ui_record_not_found
  rescue_from ActionController::InvalidAuthenticityToken, with: :ui_expired_session

  private

  # A validated browser preference; message language and AI consent are independent.
  def with_interface_locale(&action)
    supported = I18n.available_locales.map(&:to_s)
    requested = params[:ui_locale].is_a?(String) ? params[:ui_locale] : nil
    if request.get? && request.format.html? && supported.include?(requested)
      cookies[:turbo_chat_ui_locale] = {
        value: requested, expires: 1.year.from_now,
        same_site: :lax, secure: Rails.env.production?
      }
    end
    selected = if request.get? && request.format.html? && supported.include?(requested)
      requested
    else
      cookies[:turbo_chat_ui_locale]
    end
    I18n.with_locale(supported.include?(selected) ? selected : I18n.default_locale, &action)
  end

  def ui_error_html_request?
    return false if request.xhr? || request.format.json? || request.format.turbo_stream?
    return false if %w[chat_attachments user_avatars].include?(controller_path)
    request.format.html? || request.headers["Accept"].to_s.include?("text/html")
  end

  def render_ui_error(status)
    room = instance_variable_defined?(:@room) ? @room : nil
    member = room && current_user && room.accessible_to?(current_user)
    @ui_error = UiErrorState.for(status: status,
      controller_path: controller_path, room_member: !!member)
    response.headers["X-Relay-Error-State"] = @ui_error.key
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    render "shared/ui_error_state", status: @ui_error.status,
      formats: [:html], layout: "application"
  end

  def ui_record_not_found(error)
    raise error unless ui_error_html_request?
    render_ui_error(:not_found)
  end

  def ui_expired_session(error)
    raise error unless ui_error_html_request?
    render_ui_error(:unprocessable_entity)
  end


  def turbo_frame_request_variant
    request.variant = :turbo_frame if turbo_frame_request?
  end
end
