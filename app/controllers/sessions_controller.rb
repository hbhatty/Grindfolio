class SessionsController < ApplicationController
  LOGIN_RATE_LIMIT = 10
  LOGIN_RATE_LIMIT_WINDOW = 3.minutes

  protect_from_forgery with: :exception
  rate_limit to: LOGIN_RATE_LIMIT,
    within: LOGIN_RATE_LIMIT_WINDOW,
    only: :create,
    with: -> { render :rate_limited, status: :too_many_requests }

  def new
    redirect_to root_path if Current.session

    @password_credential ||= PasswordCredential.new
  end

  def create
    return redirect_to(root_path, status: :see_other) if Current.session

    @password_credential = PasswordCredential.authenticate_by(
      email_address: normalized_email,
      password: login_params[:password]
    )

    if @password_credential&.email_verified_at? && start_session_for(@password_credential)
      redirect_to root_path, status: :see_other
    else
      @password_credential = PasswordCredential.new(email_address: normalized_email)
      @password_credential.errors.add(:base, "Invalid email address or password.")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_current_session
    redirect_to root_path, status: :see_other
  end

  private
    def normalized_email
      PasswordCredential.new(email_address: login_params[:email_address]).email_address
    end

    def start_session_for(password_credential)
      started = false

      PasswordCredential.transaction do
        credential = PasswordCredential.lock.find_by(id: password_credential.id)

        if credential&.email_verified_at? && credential.authenticate(login_params[:password])
          start_new_session_for(credential.user)
          started = true
        end
      end

      started
    end

    def login_params
      params.fetch(:session, ActionController::Parameters.new).permit(:email_address, :password)
    end
end
