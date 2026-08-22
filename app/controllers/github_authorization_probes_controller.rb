class GithubAuthorizationProbesController < ApplicationController
  before_action :require_authentication

  def show
    authorization = request.env["omniauth.auth"]
    return render_failure unless authorization

    @oauth_identity = {
      uid: authorization.uid,
      login: authorization.info.nickname
    }
    @token_metadata = token_metadata(authorization.credentials)
    @probe = Github::ContributionProbe.new(
      access_token: authorization.credentials.token
    ).call
  rescue Github::ContributionProbe::Error => error
    Rails.logger.warn("GitHub authorization probe failed: #{error.message}")
    render_failure
  end

  def failure
    render_failure
  end

  private
    def token_metadata(credentials)
      {
        expires: credentials.expires == true,
        expires_at: credentials.expires_at && Time.zone.at(credentials.expires_at),
        refresh_token_present: credentials.refresh_token.present?,
        granted_scope: credentials.scope.presence || "none"
      }
    end

    def render_failure
      render :failure, status: :unprocessable_entity
    end
end
