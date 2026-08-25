require "test_helper"

class LeetcodeDailyActivityTest < ActiveSupport::TestCase
  setup do
    @connection = User.create!.create_leetcode_connection!(
      username: "exampleuser",
      tracking_started_on: Date.new(2026, 8, 5),
      verified_at: Time.utc(2026, 8, 5, 12)
    )
  end

  test "stores one nonnegative submission total per tracked UTC date" do
    activity = @connection.daily_activities.create!(
      activity_date: Date.new(2026, 8, 7),
      submission_count: 4
    )
    duplicate = @connection.daily_activities.build(
      activity_date: activity.activity_date,
      submission_count: 1
    )
    negative = @connection.daily_activities.build(
      activity_date: Date.new(2026, 8, 8),
      submission_count: -1
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:activity_date], "has already been taken"
    assert_not negative.valid?
    assert_includes negative.errors[:submission_count], "must be greater than or equal to 0"
  end

  test "rejects activity before the connection tracking boundary" do
    activity = @connection.daily_activities.build(
      activity_date: Date.new(2026, 8, 4),
      submission_count: 3
    )

    assert_not activity.valid?
    assert_includes activity.errors[:activity_date], "cannot be before LeetCode tracking started"
  end

  test "removing the user removes its cached LeetCode activity" do
    activity = @connection.daily_activities.create!(
      activity_date: Date.new(2026, 8, 5),
      submission_count: 1
    )

    @connection.user.destroy!

    assert_not LeetcodeDailyActivity.exists?(activity.id)
  end
end
