# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :limit_registration_requests, only: [:create, :update]
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]
  before_action :reject_unsafe_avatar_upload, only: %i[create update]

  # GET /resource/sign_up
  # def new
  #   super
  # end

  # POST /resource
  # def create
  #   super
  # end

  # GET /resource/edit
  # def edit
  #   super
  # end

  # PUT /resource
  # def update
  #   super
  # end

  # DELETE /resource
  # def destroy
  #   super
  # end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  private

  def reject_unsafe_avatar_upload
    return unless params[:user].is_a?(ActionController::Parameters)

    error = AttachmentUploadGuard.avatar_error_for(params[:user][:avatar])
    return unless error

    destination = action_name == "create" ? new_user_registration_path : edit_user_registration_path
    redirect_to destination, alert: error, status: :see_other
  end

  def limit_registration_requests
    enforce_request_limit(scope: "account-change", limit: 5, period: 10.minutes, identity: "ip:#{request.remote_ip}")
  end

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:avatar, :display_name])
  end

  # If you have extra params to permit, append them to the sanitizer.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:avatar, :display_name])
  end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end
end
