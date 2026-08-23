require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "can exist without a password credential" do
    user = User.create!

    assert_nil user.password_credential
  end

  test "can exist without a time zone before account setup" do
    user = User.create!

    assert_nil user.time_zone
  end

  test "accepts an IANA time zone identifier" do
    user = User.new(time_zone: "America/Toronto")

    assert_predicate user, :valid?
  end

  test "rejects blank and invalid time zone identifiers" do
    [ "", "Eastern Time (US & Canada)", "Not/A_Time_Zone" ].each do |time_zone|
      user = User.new(time_zone:)

      assert_not user.valid?
      assert_includes user.errors[:time_zone], "is not a valid IANA time zone"
    end
  end

  test "destroys its password credential" do
    user = User.create!
    credential = user.create_password_credential!(
      email_address: "developer@example.com",
      password: "correct horse battery staple",
      password_confirmation: "correct horse battery staple"
    )

    assert_difference -> { PasswordCredential.count }, -1 do
      user.destroy!
    end
    assert_not PasswordCredential.exists?(credential.id)
  end

  test "destroys its external identities and their GitHub activity" do
    user = User.create!
    identity = user.external_identities.create!(provider: "github", provider_uid: "github-id")
    connection = identity.create_github_connection!(
      tracking_started_on: Date.new(2026, 8, 22),
      access_token: "access-token",
      refresh_token: "refresh-token",
      access_token_expires_at: Time.utc(2026, 8, 22, 20)
    )
    contribution = connection.daily_contributions.create!(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: 1
    )

    user.destroy!

    assert_not ExternalIdentity.exists?(identity.id)
    assert_not GithubConnection.exists?(connection.id)
    assert_not GithubDailyContribution.exists?(contribution.id)
  end
end
