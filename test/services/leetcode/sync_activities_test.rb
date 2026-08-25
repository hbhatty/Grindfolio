require "test_helper"

class Leetcode::SyncActivitiesTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 7)
  NOW = Time.utc(2026, 8, 7, 14, 30)

  class FakeCalendarFactory
    attr_accessor :result, :error
    attr_reader :calls

    def initialize(result: nil, error: nil)
      @result = result
      @error = error
      @calls = []
    end

    def new(**arguments)
      calls << arguments
      factory = self
      Object.new.tap do |client|
        client.define_singleton_method(:call) do
          raise factory.error if factory.error

          factory.result
        end
      end
    end
  end

  setup do
    @connection = User.create!.create_leetcode_connection!(
      username: "ExampleUser",
      tracking_started_on: Date.new(2026, 8, 5),
      verified_at: Time.utc(2026, 8, 5, 12)
    )
  end

  test "one current UTC year request materializes zero days and excludes boundary leakage" do
    calendar = FakeCalendarFactory.new(
      result: calendar_result(
        days: [
          day(Date.new(2026, 8, 4), 9),
          day(TODAY, 4),
          day(Date.new(2026, 8, 8), 7)
        ]
      )
    )
    @connection.update!(last_sync_error: "previous sanitized failure")

    result = sync(calendar:)

    assert_equal Date.new(2026, 8, 5), result.from_date
    assert_equal TODAY, result.to_date
    assert_equal 3, result.days_synchronized
    assert_equal NOW, result.synced_at
    assert_equal [
      [ Date.new(2026, 8, 5), 0 ],
      [ Date.new(2026, 8, 6), 0 ],
      [ TODAY, 4 ]
    ], @connection.daily_activities.order(:activity_date).pluck(:activity_date, :submission_count)
    assert_equal [ { username: "ExampleUser", year: 2026 } ], calendar.calls
    assert_equal NOW, @connection.last_synced_at
    assert_nil @connection.last_sync_error
  end

  test "a retry authoritatively corrects counts without duplicates" do
    calendar = FakeCalendarFactory.new(result: calendar_result(days: [ day(TODAY, 4) ]))
    sync(calendar:)
    original = @connection.daily_activities.find_by!(activity_date: TODAY)

    calendar.result = calendar_result(days: [ day(TODAY, 2) ])
    assert_no_difference -> { LeetcodeDailyActivity.count } do
      sync(calendar:, now: NOW + 5.minutes)
    end

    corrected = @connection.daily_activities.find_by!(activity_date: TODAY)
    assert_equal 2, corrected.submission_count
    assert_equal original.created_at, corrected.created_at
    assert_equal NOW + 5.minutes, corrected.updated_at
    assert_equal 2, calendar.calls.length
  end

  test "provider failure preserves cached rows and successful timestamp while storing only a fixed error" do
    calendar = FakeCalendarFactory.new(result: calendar_result(days: [ day(TODAY, 4) ]))
    sync(calendar:)
    successful_timestamp = @connection.last_synced_at
    cached_rows = cached_activity
    provider_error = Leetcode::SubmissionCalendar::Unavailable.new("private provider response")
    calendar.error = provider_error

    error = assert_raises Leetcode::SyncActivities::Error do
      sync(calendar:, now: NOW + 1.hour)
    end

    assert_equal "LeetCode activity could not be synchronized", error.message
    assert_same provider_error, error.cause
    assert_equal cached_rows, cached_activity
    assert_equal successful_timestamp, @connection.last_synced_at
    assert_equal Leetcode::SyncActivities::STORED_ERROR_MESSAGE, @connection.last_sync_error
    assert_not_includes @connection.last_sync_error, "private provider response"
    assert_equal 2, calendar.calls.length
  end

  test "access blocks preserve cached activity and successful timestamp while storing only the fixed error" do
    calendar = FakeCalendarFactory.new(result: calendar_result(days: [ day(TODAY, 4) ]))
    sync(calendar:)
    successful_timestamp = @connection.last_synced_at
    cached_rows = cached_activity
    provider_error = Leetcode::SubmissionCalendar::AccessBlocked.new("private challenge details")
    calendar.error = provider_error

    error = assert_raises Leetcode::SyncActivities::AccessBlocked do
      sync(calendar:, now: NOW + 1.hour)
    end

    assert_equal "LeetCode access controls blocked activity synchronization", error.message
    assert_same provider_error, error.cause
    assert_equal cached_rows, cached_activity
    assert_equal successful_timestamp, @connection.last_synced_at
    assert_equal Leetcode::SyncActivities::STORED_ERROR_MESSAGE, @connection.last_sync_error
    assert_not_includes @connection.last_sync_error, "private challenge details"
    assert_equal 2, calendar.calls.length
  end

  test "canonical username mismatch preserves cached rows and successful timestamp" do
    calendar = FakeCalendarFactory.new(result: calendar_result(days: [ day(TODAY, 4) ]))
    sync(calendar:)
    successful_timestamp = @connection.last_synced_at
    cached_rows = cached_activity
    calendar.result = calendar_result(username: "DifferentUser", days: [ day(TODAY, 99) ])

    error = assert_raises Leetcode::SyncActivities::IdentityMismatch do
      sync(calendar:, now: NOW + 1.hour)
    end

    assert_equal "LeetCode returned a different canonical username", error.message
    assert_equal cached_rows, cached_activity
    assert_equal successful_timestamp, @connection.last_synced_at
    assert_equal Leetcode::SyncActivities::STORED_ERROR_MESSAGE, @connection.last_sync_error
  end

  test "invalid later calendar data cannot cause partial writes" do
    calendar = FakeCalendarFactory.new(
      result: calendar_result(
        days: [
          day(Date.new(2026, 8, 5), 3),
          day(Date.new(2026, 8, 6), -1)
        ]
      )
    )

    assert_raises Leetcode::SyncActivities::InvalidCalendar do
      sync(calendar:)
    end

    assert_empty @connection.daily_activities
    assert_nil @connection.last_synced_at
    assert_equal Leetcode::SyncActivities::STORED_ERROR_MESSAGE, @connection.last_sync_error
  end

  test "duplicate provider dates are rejected instead of being added together" do
    duplicate_date = Date.new(2026, 8, 6)
    calendar = FakeCalendarFactory.new(
      result: calendar_result(days: [ day(duplicate_date, 2), day(duplicate_date, 3) ])
    )

    assert_raises Leetcode::SyncActivities::InvalidCalendar do
      sync(calendar:)
    end

    assert_empty @connection.daily_activities
    assert_nil @connection.last_synced_at
  end

  private
    def sync(calendar:, now: NOW)
      Leetcode::SyncActivities.new(
        connection: @connection,
        today: TODAY,
        now:,
        calendar_client: calendar
      ).call
    end

    def calendar_result(username: "ExampleUser", days: [])
      Leetcode::SubmissionCalendar::Result.new(username:, days:)
    end

    def day(activity_date, submission_count)
      Leetcode::SubmissionCalendar::Day.new(activity_date:, submission_count:)
    end

    def cached_activity
      @connection.daily_activities.order(:activity_date).pluck(
        :activity_date,
        :submission_count,
        :created_at,
        :updated_at
      )
    end
end
