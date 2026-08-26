module Notion
  class OauthState
    PURPOSE = "notion_oauth"
    EXPIRES_IN = 10.minutes

    class Error < StandardError; end

    def self.issue(session:)
      verifier.generate(
        { session_id: session.id, user_id: session.user_id },
        expires_in: EXPIRES_IN,
        purpose: PURPOSE
      )
    end

    def self.verify!(token:, session:)
      payload = verifier.verify(token, purpose: PURPOSE)
      return true if payload["session_id"] == session.id && payload["user_id"] == session.user_id

      raise Error, "Notion OAuth state is not bound to the current session"
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Error, "Notion OAuth state is invalid or expired"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
