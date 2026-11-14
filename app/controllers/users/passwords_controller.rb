# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # No production reset links or tokens until SMTP sender, HTTPS URLs and
  # end-to-end email delivery have been verified separately.
  prepend_before_action :deny_unverified_recovery!, only: %i[new create edit update]

  private

  def deny_unverified_recovery!
    head :not_found unless DemoAccessPolicy.password_recovery_available?
  end

  public
  # GET /resource/password/new
  # def new
  #   super
  # end

  # POST /resource/password
  # def create
  #   super
  # end

  # GET /resource/password/edit?reset_password_token=abcdef
  # def edit
  #   super
  # end

  # PUT /resource/password
  # def update
  #   super
  # end

  # protected

  # def after_resetting_password_path_for(resource)
  #   super(resource)
  # end

  # The path used after sending reset password instructions
  # def after_sending_reset_password_instructions_path_for(resource_name)
  #   super(resource_name)
  # end
end
