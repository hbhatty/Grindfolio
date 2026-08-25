require "securerandom"

class LeetcodeVerificationChallenge < ApplicationRecord
  LIFETIME = 15.minutes
  MAX_ATTEMPTS = 5
  TOKEN_PREFIX = "grindfolio-verify-"

  encrypts :token

  belongs_to :user

  normalizes :requested_username, with: ->(username) { username.strip }

  validates :requested_username,
    presence: true,
    length: { maximum: 64 },
    format: {
      with: /\A[^\s\/]+\z/,
      message: "must be a LeetCode username"
    }
  validates :token, :expires_at, presence: true
  validates :verification_attempts,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: MAX_ATTEMPTS
    }

  def self.issue_for!(user:, requested_username:, now: Time.current)
    user.with_lock do
      user.leetcode_verification_challenges.where(consumed_at: nil).delete_all
      user.leetcode_verification_challenges.create!(
        requested_username:,
        token: "#{TOKEN_PREFIX}#{SecureRandom.hex(12)}",
        expires_at: now + LIFETIME
      )
    end
  end

  def usable?(now: Time.current)
    consumed_at.nil? && expires_at > now && verification_attempts < MAX_ATTEMPTS
  end

  def claim_attempt!(now: Time.current)
    with_lock do
      return false unless usable?(now:)

      increment!(:verification_attempts)
      true
    end
  end
end
