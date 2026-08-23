class GithubConnectionsController < ApplicationController
  before_action :require_authentication

  def callback
    authorization = request.env["omniauth.auth"]
    return render_failure unless authorization

    connection = Github::ConnectAccount.new(
      user: Current.user,
      authorization:
    ).call

    redirect_to account_path,
      notice: "GitHub connected as #{connection.external_identity.provider_username}.",
      status: :see_other
  rescue Github::ConnectAccount::Error => error
    Rails.logger.warn("GitHub connection failed (#{error.class.name})")
    render_failure
  end

  def failure
    render_failure
  end

  private
    def render_failure
      render :failure, status: :unprocessable_entity
    end
end
