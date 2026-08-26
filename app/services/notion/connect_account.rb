module Notion
  class ConnectAccount
    class Error < StandardError; end

    def self.call(user:, authorization:, now: Time.current)
      new(user:, authorization:, now:).call
    end

    def initialize(user:, authorization:, now:)
      @user = user
      @authorization = authorization
      @now = now
    end

    def call
      user.with_lock do
        connection = user.notion_connection
        reject_different_workspace!(connection)
        reject_claimed_authorization!(connection)

        if connection
          connection.update!(authorization_attributes)
          connection
        else
          user.create_notion_connection!(
            **authorization_attributes,
            tracking_started_on: tracking_date,
            authorized_at: now
          )
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, KeyError, TypeError => error
      raise Error, "Notion authorization could not be saved", cause: error
    end

    private
      attr_reader :user, :authorization, :now

      def authorization_attributes
        {
          workspace_id: required_value(:workspace_id),
          workspace_name: authorization[:workspace_name].presence,
          bot_id: required_value(:bot_id),
          owner_user_id: authorization[:owner_user_id].presence,
          access_token: required_value(:access_token),
          refresh_token: required_value(:refresh_token)
        }
      end

      def required_value(key)
        value = authorization.fetch(key)
        raise TypeError unless value.is_a?(String) && value.present?

        value
      end

      def reject_different_workspace!(connection)
        return unless connection
        return if connection.workspace_id == required_value(:workspace_id)

        raise Error, "A different Notion workspace is already connected"
      end

      def reject_claimed_authorization!(connection)
        claimed = NotionConnection.find_by(bot_id: required_value(:bot_id))
        return if claimed.nil? || claimed == connection

        raise Error, "This Notion authorization is unavailable"
      end

      def tracking_date
        now.in_time_zone(user.time_zone.presence || "UTC").to_date
      end
  end
end
