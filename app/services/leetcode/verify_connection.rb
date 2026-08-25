module Leetcode
  class VerifyConnection
    class Error < StandardError; end
    class AlreadyConnected < Error; end
    class ChallengeMissing < Error; end
    class InvalidChallenge < Error; end
    class UsernameUnavailable < Error; end

    def initialize(user:, challenge:, profile_client: nil, now: Time.current)
      @user = user
      @challenge = challenge
      @profile_client = profile_client || PublicProfile.new(username: challenge.requested_username)
      @now = now
    end

    def call
      raise InvalidChallenge, "LeetCode challenge does not belong to this user" unless challenge.user_id == user.id
      raise InvalidChallenge, "LeetCode challenge is no longer usable" unless challenge.claim_attempt!(now:)

      profile = profile_client.call
      raise ChallengeMissing, "LeetCode challenge was not found" unless profile.about_me.include?(challenge.token)

      create_connection!(profile.username)
    end

    private
      attr_reader :user, :challenge, :profile_client, :now

      def create_connection!(canonical_username)
        user.with_lock do
          challenge.lock!
          raise InvalidChallenge, "LeetCode challenge is no longer usable" if challenge.consumed_at? || challenge.expires_at <= now
          raise AlreadyConnected, "Grindfolio user already has a LeetCode connection" if LeetcodeConnection.exists?(user_id: user.id)

          connection = user.create_leetcode_connection!(
            username: canonical_username,
            tracking_started_on: now.utc.to_date,
            verified_at: now
          )
          challenge.update!(consumed_at: now)
          connection
        end
      rescue ActiveRecord::RecordNotUnique
        raise UsernameUnavailable, "LeetCode username is already connected"
      rescue ActiveRecord::RecordInvalid => error
        if error.record.is_a?(LeetcodeConnection) && error.record.errors[:username].any?
          raise UsernameUnavailable, "LeetCode username is already connected"
        end

        raise
      end
  end
end
