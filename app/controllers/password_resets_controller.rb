class PasswordResetsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :load_password_credential

  def show
    render_invalid unless @password_credential
  end

  def update
    result, reset_user_id = reset_password

    case result
    when :updated
      destination, notice = reset_completion_for(reset_user_id)
      redirect_to destination, notice:, status: :see_other
    when :invalid_password
      render :show, status: :unprocessable_entity
    else
      render_invalid
    end
  end

  private
    def load_password_credential
      @password_credential = PasswordCredential.find_by_token_for(
        :password_reset,
        params[:token]
      )
    end

    def reset_password
      result = :invalid_token
      reset_user_id = nil

      PasswordCredential.transaction do
        credential = PasswordCredential.lock.find_by(id: @password_credential&.id)
        token_credential = credential && PasswordCredential.find_by_token_for(
          :password_reset,
          params[:token]
        )

        next unless credential && token_credential&.id == credential.id

        credential.assign_attributes(password_reset_params)
        @password_credential = credential

        if credential.save
          user = User.lock.find(credential.user_id)
          user.sessions.delete_all
          result = :updated
          reset_user_id = user.id
        else
          result = :invalid_password
        end
      end

      [ result, reset_user_id ]
    end

    def password_reset_params
      params.require(:password_reset).permit(:password, :password_confirmation)
    end

    def reset_completion_for(reset_user_id)
      if Current.session && Current.session.user_id != reset_user_id
        [
          root_path,
          "The password has been reset. Sign out before signing in with the new password."
        ]
      else
        Current.session = nil
        clear_session_cookie
        [
          sign_in_path,
          "Your password has been reset. Sign in with your new password."
        ]
      end
    end

    def render_invalid
      render :invalid, status: :unprocessable_entity
    end
end
