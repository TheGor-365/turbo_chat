# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  before_action :limit_login_attempts, only: :create
  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  def destroy
    ActionCable.server.remote_connections.where(current_user: current_user).disconnect
    current_user.update(status: User.statuses[:offline])
    super
  end

  private

  def limit_login_attempts
    enforce_request_limit(scope: "session-login", limit: 10, period: 10.minutes, identity: "ip:#{request.remote_ip}")
  end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end
