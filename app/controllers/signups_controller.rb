class SignupsController < ApplicationController
  SIGNUP_RATE_LIMIT = 10
  SIGNUP_RATE_LIMIT_WINDOW = 3.minutes

  protect_from_forgery with: :exception
  rate_limit to: SIGNUP_RATE_LIMIT,
    within: SIGNUP_RATE_LIMIT_WINDOW,
    only: :create,
    with: -> { render :rate_limited, status: :too_many_requests }

  def new
    @password_credential = PasswordCredential.new
  end

  def success
  end

  def create
    build_account

    if @password_credential.valid? && save_account
      EmailVerificationMailer.verify(@password_credential).deliver_later
      redirect_to sign_up_success_path, status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def build_account
      @user = User.new
      @password_credential = @user.build_password_credential(signup_params)
    end

    def save_account
      User.transaction do
        @user.save!
        @password_credential.save!
      end
      true
    rescue ActiveRecord::RecordNotUnique
      @password_credential.errors.add(:email_address, :taken)
      false
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record == @password_credential

      false
    end

    def signup_params
      params.require(:signup).permit(:email_address, :password, :password_confirmation)
    end
end
