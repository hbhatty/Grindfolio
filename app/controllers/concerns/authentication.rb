module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :restore_session
  end

  private
    def require_authentication
      return if Current.user

      redirect_to sign_in_path, alert: "Please sign in to continue.", status: :see_other
    end

    def start_new_session_for(user)
      Current.session = user.sessions.create!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      write_session_cookie(Current.session)
    end

    def terminate_current_session
      Current.session&.destroy!
      Current.session = nil
      clear_session_cookie
    end

    def write_session_cookie(session)
      cookies.signed[Session::COOKIE_NAME] = session_cookie_options(session)
    end

    def session_cookie_options(session)
      {
        value: session.id,
        expires: session.expires_at,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
    end

    def restore_session
      return if Current.session

      session_id = cookies.signed[Session::COOKIE_NAME]
      if session_id
        session = Session.find_by(id: session_id)
        current_time = Time.current

        if session&.active?(at: current_time)
          session.refresh_activity!(at: current_time)
          Current.session = session
        elsif session
          session.destroy!
          clear_session_cookie
        else
          clear_session_cookie
        end
      elsif session_cookie_present?
        clear_session_cookie
      end
    end

    def session_cookie_present?
      # The raw value is used only to distinguish a missing cookie from a
      # tampered one; session identity always comes from the signed jar above.
      request.cookies.key?(Session::COOKIE_NAME.to_s)
    end

    def clear_session_cookie
      cookies.delete(
        Session::COOKIE_NAME,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      )
    end
end
