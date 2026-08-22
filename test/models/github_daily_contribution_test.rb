require "test_helper"

class GithubDailyContributionTest < ActiveSupport::TestCase
  setup do
    user = User.create!
    identity = user.external_identities.create!(provider: "github", provider_uid: "github-id")
    @connection = identity.create_github_connection!(tracking_started_on: Date.new(2026, 8, 22))
  end

  test "stores one official daily count and level on or after tracking starts" do
    contribution = @connection.daily_contributions.create!(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: 3,
      contribution_level: "SECOND_QUARTILE"
    )

    assert_equal 3, contribution.contribution_count
    assert_equal "SECOND_QUARTILE", contribution.contribution_level
  end

  test "distinguishes a tracked zero from a date before tracking" do
    tracked_zero = @connection.daily_contributions.build(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: 0,
      contribution_level: "NONE"
    )
    before_tracking = @connection.daily_contributions.build(
      activity_date: Date.new(2026, 8, 21),
      contribution_count: 0,
      contribution_level: "NONE"
    )

    assert_predicate tracked_zero, :valid?
    assert_not before_tracking.valid?
    assert_includes before_tracking.errors[:activity_date], "cannot be before GitHub tracking started"
  end

  test "rejects negative counts and unsupported contribution levels" do
    contribution = @connection.daily_contributions.build(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: -1,
      contribution_level: "BUSY"
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:contribution_count], "must be greater than or equal to 0"
    assert_includes contribution.errors[:contribution_level], "is not included in the list"
  end

  test "allows only one authoritative total per connection and date" do
    @connection.daily_contributions.create!(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: 1
    )
    duplicate = @connection.daily_contributions.build(
      activity_date: Date.new(2026, 8, 22),
      contribution_count: 2
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:activity_date], "has already been taken"
  end

  test "database constraints reject a negative contribution count" do
    assert_raises ActiveRecord::StatementInvalid do
      GithubDailyContribution.insert!({
        github_connection_id: @connection.id,
        activity_date: Date.new(2026, 8, 22),
        contribution_count: -1,
        contribution_level: "NONE",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end
end
