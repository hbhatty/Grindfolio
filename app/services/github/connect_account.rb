module Github
  class ConnectAccount
    class Error < StandardError; end
    class IdentityAlreadyConnected < Error; end
    class DifferentIdentityAlreadyConnected < Error; end

    def initialize(user:, authorization:, tracking_date: nil)
      @user = user
      @authorization = authorization
      @tracking_date = tracking_date || default_tracking_date
    end

    def call
      validate_authorization!

      ExternalIdentity.transaction do
        identity = find_or_initialize_identity
        update_identity!(identity)
        create_or_update_connection!(identity)
      end
    rescue ActiveRecord::RecordNotUnique
      raise IdentityAlreadyConnected, "GitHub account is already connected"
    rescue ActiveRecord::RecordInvalid => error
      raise Error, "GitHub connection could not be saved", cause: error
    end

    private
      attr_reader :user, :authorization, :tracking_date

      def default_tracking_date
        Time.current.in_time_zone(user.time_zone.presence || "UTC").to_date
      end

      def validate_authorization!
        return if provider_uid.present? && provider_username.present? &&
          access_token.present? && refresh_token.present? && access_token_expires_at.present?

        raise Error, "GitHub authorization credentials are incomplete"
      end

      def find_or_initialize_identity
        claimed_identity = ExternalIdentity.github.lock.find_by(provider_uid:)

        if claimed_identity && claimed_identity.user_id != user.id
          raise IdentityAlreadyConnected, "GitHub account is already connected"
        end

        existing_identity = user.external_identities.github.lock.first
        if existing_identity && existing_identity.provider_uid != provider_uid
          raise DifferentIdentityAlreadyConnected, "A different GitHub account is already connected"
        end

        claimed_identity || existing_identity || user.external_identities.build(provider: "github")
      end

      def update_identity!(identity)
        identity.update!(
          provider_uid:,
          provider_username:,
          provider_email: authorization_value(:info, :email),
          profile_image_url: authorization_value(:info, :image)
        )
      end

      def create_or_update_connection!(identity)
        connection = GithubConnection.lock.find_by(external_identity: identity)
        return create_connection!(identity) unless connection

        # A fresh authorization can safely replace credentials even if an old
        # encryption key is no longer available. Avoid reading the old
        # ciphertext while Rails serializes the newly authorized values.
        connection.update_columns(
          access_token:,
          refresh_token:,
          access_token_expires_at:,
          refresh_token_expires_at: nil,
          updated_at: Time.current
        )
        connection
      end

      def create_connection!(identity)
        identity.create_github_connection!(
          tracking_started_on: tracking_date,
          access_token:,
          refresh_token:,
          access_token_expires_at:
        )
      end

      def provider_uid
        @provider_uid ||= authorization_value(:uid).to_s.presence
      end

      def provider_username
        @provider_username ||= authorization_value(:info, :nickname).to_s.presence
      end

      def access_token
        @access_token ||= authorization_value(:credentials, :token).to_s.presence
      end

      def refresh_token
        @refresh_token ||= authorization_value(:credentials, :refresh_token).to_s.presence
      end

      def access_token_expires_at
        expires_at = authorization_value(:credentials, :expires_at)
        @access_token_expires_at ||= Time.zone.at(Integer(expires_at)) if expires_at
      rescue ArgumentError, TypeError
        nil
      end

      def authorization_value(*keys)
        return unless authorization.respond_to?(:dig)

        authorization.dig(*keys.map(&:to_s)) || authorization.dig(*keys.map(&:to_sym))
      end
  end
end
