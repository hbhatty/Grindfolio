require "uri"

class NotionConnectionsController < ApplicationController
  AUTHORIZATION_ENDPOINT = "https://api.notion.com/v1/oauth/authorize"
  class_attribute :authorization_exchange, default: Notion::ExchangeAuthorizationCode

  before_action :require_authentication

  def create
    state = Notion::OauthState.issue(session: Current.session)
    redirect_to authorization_url(state), allow_other_host: true
  end

  def callback
    Notion::OauthState.verify!(token: params[:state].to_s, session: Current.session)
    return render_failure if params[:error].present?

    authorization = authorization_exchange.call(
      code: params[:code].to_s,
      redirect_uri: notion_connection_callback_url
    )
    connection = Notion::ConnectAccount.call(user: Current.user, authorization:)

    workspace = connection.workspace_name.presence || "your workspace"
    redirect_to account_path,
      notice: "Notion connected to #{workspace}.",
      status: :see_other
  rescue Notion::OauthState::Error,
    Notion::ExchangeAuthorizationCode::Error,
    Notion::ConnectAccount::Error => error
    Rails.logger.warn("Notion connection failed (#{error.class.name})")
    render_failure
  end

  private
    def authorization_url(state)
      query = URI.encode_www_form(
        owner: "user",
        client_id: Rails.application.config.x.notion.client_id,
        redirect_uri: notion_connection_callback_url,
        response_type: "code",
        state:
      )
      "#{AUTHORIZATION_ENDPOINT}?#{query}"
    end

    def render_failure
      render :failure, status: :unprocessable_entity
    end
end
