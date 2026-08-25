require "test_helper"

class LeetcodeVerificationChallengeTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 8, 24, 4, 30)

  test "issues a user-bound encrypted short-lived challenge" do
    user = User.create!
    challenge = LeetcodeVerificationChallenge.issue_for!(
      user:,
      requested_username: "  exampleuser  ",
      now: NOW
    )

    raw_token = LeetcodeVerificationChallenge.connection.select_value(<<~SQL)
      SELECT token
      FROM leetcode_verification_challenges
      WHERE id = #{challenge.id}
    SQL

    assert_equal user, challenge.user
    assert_equal "exampleuser", challenge.requested_username
    assert_match(/\Agrindfolio-verify-[0-9a-f]{24}\z/, challenge.token)
    assert_equal NOW + 15.minutes, challenge.expires_at
    assert_equal 0, challenge.verification_attempts
    assert_not_equal challenge.token, raw_token
    assert_not_includes raw_token, challenge.token
  end

  test "issuing a replacement invalidates the previous unconsumed challenge" do
    user = User.create!
    previous = LeetcodeVerificationChallenge.issue_for!(
      user:,
      requested_username: "first-user",
      now: NOW
    )

    replacement = LeetcodeVerificationChallenge.issue_for!(
      user:,
      requested_username: "second-user",
      now: NOW + 1.minute
    )

    assert_not LeetcodeVerificationChallenge.exists?(previous.id)
    assert_equal replacement, user.leetcode_verification_challenges.find_by!(consumed_at: nil)
    assert_equal "second-user", replacement.requested_username
  end

  test "claims at most five attempts while active" do
    challenge = LeetcodeVerificationChallenge.issue_for!(
      user: User.create!,
      requested_username: "exampleuser",
      now: NOW
    )

    5.times { assert challenge.claim_attempt!(now: NOW + 1.minute) }

    assert_equal 5, challenge.reload.verification_attempts
    assert_not challenge.claim_attempt!(now: NOW + 1.minute)
    assert_equal 5, challenge.reload.verification_attempts
  end

  test "does not claim expired or consumed challenges" do
    expired = LeetcodeVerificationChallenge.issue_for!(
      user: User.create!,
      requested_username: "expired-user",
      now: NOW
    )
    consumed = LeetcodeVerificationChallenge.issue_for!(
      user: User.create!,
      requested_username: "consumed-user",
      now: NOW
    )
    consumed.update!(consumed_at: NOW + 1.minute)

    assert_not expired.claim_attempt!(now: NOW + 15.minutes)
    assert_not consumed.claim_attempt!(now: NOW + 1.minute)
    assert_equal 0, expired.reload.verification_attempts
    assert_equal 0, consumed.reload.verification_attempts
  end

  test "rejects values that are not plain LeetCode usernames" do
    user = User.create!

    [ "", "two words", "https://leetcode.com/u/exampleuser/" ].each do |username|
      challenge = user.leetcode_verification_challenges.build(
        requested_username: username,
        token: "grindfolio-verify-token",
        expires_at: NOW + 15.minutes
      )

      assert_not challenge.valid?, username
      assert challenge.errors[:requested_username].any?, username
    end
  end
end
