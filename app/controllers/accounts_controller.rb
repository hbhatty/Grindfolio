class AccountsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :require_authentication
  before_action :load_account

  def show
  end

  def update
    if @user.update(account_params)
      redirect_to account_path, notice: "Your time zone has been saved.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def load_account
      @user = Current.user
      credential = @user.password_credential
      @verified_email_address = credential.email_address if credential&.email_verified_at?
    end

    def account_params
      params.require(:user).permit(:time_zone)
    end
end
