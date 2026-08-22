class EmailVerificationsController < ApplicationController
  SESSION_COOKIE_NAME = Session::COOKIE_NAME

  protect_from_forgery with: :exception
  before_action :load_password_credential

  def show
    if @password_credential
      @verification_token = params[:token]
      render :show
    else
      render_invalid
    end
  end

  def confirm
    session = confirm_email

    if session
      write_session_cookie(session)
      redirect_to root_path, notice: "Your email has been verified."
    else
      render_invalid
    end
  end

  private
    def load_password_credential
      @password_credential = PasswordCredential.find_by_token_for(
        :email_verification,
        params[:token]
      )
      @password_credential = nil if @password_credential&.email_verified_at?
    end

    def confirm_email
      session = nil

      PasswordCredential.transaction do
        credential = PasswordCredential.lock.find_by(id: @password_credential&.id)
        token_credential = credential && PasswordCredential.find_by_token_for(
          :email_verification,
          params[:token]
        )

        if credential && credential.email_verified_at.nil? && token_credential&.id == credential.id
          credential.update!(email_verified_at: Time.current)
          session = credential.user.sessions.create!(
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          )
        end
      end

      session
    end

    def render_invalid
      render :invalid, status: :unprocessable_entity
    end
end
