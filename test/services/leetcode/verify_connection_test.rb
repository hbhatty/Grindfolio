require "test_helper"

class Leetcode::VerifyConnectionTest < ActiveSupport::TestCase
  SUBMITTED_AT = Time.new(2026, 8, 23, 23, 44, 0, "-04:00")

  class FakeProfileClient
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = 0
    end

    def call
      @calls += 1
      @result
    end
  end

  test "consumes a matching challenge and starts tracking on the UTC provider date" do
    user = User.create!(time_zone: "America/Toronto")
    challenge = issue_challenge(user:)
    client = FakeProfileClient.new(
      Leetcode::PublicProfile::Result.new(
        username: "ExampleUser",
        about_me: "My profile\n#{challenge.token}"
      )
    )

    connection = Leetcode::VerifyConnection.new(
      user:,
      challenge:,
      profile_client: client,
      now: SUBMITTED_AT
    ).call

    assert_equal "ExampleUser", connection.username
    assert_equal Date.new(2026, 8, 24), connection.tracking_started_on
    assert_equal SUBMITTED_AT, connection.verified_at
    assert_equal SUBMITTED_AT, challenge.reload.consumed_at
    assert_equal 1, challenge.verification_attempts
    assert_equal 1, client.calls
  end

  test "keeps a usable challenge after the public token is missing" do
    user = User.create!
    challenge = issue_challenge(user:)
    client = FakeProfileClient.new(
      Leetcode::PublicProfile::Result.new(username: "exampleuser", about_me: "No challenge here")
    )

    assert_raises Leetcode::VerifyConnection::ChallengeMissing do
      Leetcode::VerifyConnection.new(
        user:,
        challenge:,
        profile_client: client,
        now: SUBMITTED_AT
      ).call
    end

    assert_nil user.reload.leetcode_connection
    assert_nil challenge.reload.consumed_at
    assert_equal 1, challenge.verification_attempts
  end

  test "rejects an expired or foreign challenge before a provider request" do
    owner = User.create!
    other_user = User.create!
    challenge = issue_challenge(user: owner, now: SUBMITTED_AT - 16.minutes)
    client = FakeProfileClient.new(
      Leetcode::PublicProfile::Result.new(username: "exampleuser", about_me: challenge.token)
    )

    assert_raises Leetcode::VerifyConnection::InvalidChallenge do
      Leetcode::VerifyConnection.new(
        user: owner,
        challenge:,
        profile_client: client,
        now: SUBMITTED_AT
      ).call
    end
    assert_raises Leetcode::VerifyConnection::InvalidChallenge do
      Leetcode::VerifyConnection.new(
        user: other_user,
        challenge:,
        profile_client: client,
        now: SUBMITTED_AT
      ).call
    end

    assert_equal 0, client.calls
    assert_equal 0, challenge.reload.verification_attempts
  end

  test "does not disclose which user already connected a canonical username" do
    User.create!.create_leetcode_connection!(
      username: "ExampleUser",
      tracking_started_on: Date.new(2026, 8, 24),
      verified_at: SUBMITTED_AT
    )
    user = User.create!
    challenge = issue_challenge(user:)
    client = FakeProfileClient.new(
      Leetcode::PublicProfile::Result.new(username: "exampleuser", about_me: challenge.token)
    )

    assert_raises Leetcode::VerifyConnection::UsernameUnavailable do
      Leetcode::VerifyConnection.new(
        user:,
        challenge:,
        profile_client: client,
        now: SUBMITTED_AT
      ).call
    end

    assert_nil user.reload.leetcode_connection
    assert_nil challenge.reload.consumed_at
  end

  private
    def issue_challenge(user:, now: SUBMITTED_AT - 1.minute)
      LeetcodeVerificationChallenge.issue_for!(
        user:,
        requested_username: "exampleuser",
        now:
      )
    end
end
