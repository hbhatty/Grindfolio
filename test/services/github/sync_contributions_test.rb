require "test_helper"

class Github::SyncContributionsTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 22)
  NOW = Time.utc(2026, 8, 22, 13, 30)

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

  class FakeAccessTokenFactory
    attr_reader :calls

    def initialize(token: "fresh-access-token", error: nil)
      @token = token
      @error = error
      @calls = []
    end

    def new(**arguments)
      calls << arguments
      token = @token
      error = @error
      Object.new.tap do |client|
        client.define_singleton_method(:call) do
          raise error if error

          token
        end
      end
    end
  end

  setup do
    user = User.create!
    @identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "42",
      provider_username: "old-octocat"
    )
    @connection = @identity.create_github_connection!(
      tracking_started_on: Date.new(2026, 8, 21),
      access_token: "access-token",
      refresh_token: "refresh-token",
      access_token_expires_at: Time.utc(2026, 8, 22, 20)
    )
  end

  test "stores only tracked daily totals and marks the connection ready" do
    calendar = FakeCalendarFactory.new(result: calendar_result)
    access_token = FakeAccessTokenFactory.new

    result = sync(calendar:, access_token:)

    assert_equal Date.new(2026, 8, 21), result.from_date
    assert_equal TODAY, result.to_date
    assert_equal 2, result.days_synchronized
    assert_equal NOW, result.synced_at
    assert_equal [
      [ Date.new(2026, 8, 21), 0, "NONE" ],
      [ Date.new(2026, 8, 22), 2, "SECOND_QUARTILE" ]
    ], @connection.daily_contributions.order(:activity_date).pluck(
      :activity_date,
      :contribution_count,
      :contribution_level
    )
    assert_predicate @connection, :sync_status_ready?
    assert_equal NOW, @connection.last_synced_at
    assert_nil @connection.last_sync_error
    assert_equal "octocat", @identity.reload.provider_username
    assert_equal "fresh-access-token", calendar.calls.first.fetch(:access_token)
    assert_equal @connection, access_token.calls.first.fetch(:connection)
    assert_equal NOW, access_token.calls.first.fetch(:now)
    assert_equal Date.new(2026, 8, 20), calendar.calls.first.fetch(:from_date)
    assert_equal TODAY + 1.day, calendar.calls.first.fetch(:to_date)
  end

  test "a retry updates authoritative totals instead of duplicating or adding them" do
    calendar = FakeCalendarFactory.new(result: calendar_result)
    sync(calendar:)
    original_created_at = @connection.daily_contributions.find_by!(activity_date: TODAY).created_at
    calendar.result = calendar_result(today_count: 5, today_level: "FOURTH_QUARTILE")

    assert_no_difference -> { GithubDailyContribution.count } do
      sync(calendar:, now: NOW + 5.minutes)
    end

    today = @connection.daily_contributions.find_by!(activity_date: TODAY)
    assert_equal 5, today.contribution_count
    assert_equal "FOURTH_QUARTILE", today.contribution_level
    assert_equal original_created_at, today.created_at
    assert_equal NOW + 5.minutes, today.updated_at
  end

  test "reconciles only the latest thirty tracked days without deleting older totals" do
    @connection.update!(tracking_started_on: Date.new(2026, 1, 1))
    old_day = @connection.daily_contributions.create!(
      activity_date: Date.new(2026, 2, 1),
      contribution_count: 3,
      contribution_level: "THIRD_QUARTILE"
    )
    calendar = FakeCalendarFactory.new(
      result: calendar_result(days: [ contribution_day(TODAY, 2, "SECOND_QUARTILE") ])
    )

    result = sync(calendar:)

    assert_equal TODAY - 29.days, result.from_date
    assert_equal TODAY - 30.days, calendar.calls.first.fetch(:from_date)
    assert GithubDailyContribution.exists?(old_day.id)
  end

  test "uses the user's local date and keeps only returned dates inside that window" do
    @connection.user.update!(time_zone: "America/Toronto")
    @connection.update!(tracking_started_on: Date.new(2026, 8, 22))
    calendar = FakeCalendarFactory.new(
      result: calendar_result(
        days: [
          contribution_day(Date.new(2026, 8, 21), 5, "FOURTH_QUARTILE"),
          contribution_day(Date.new(2026, 8, 22), 3, "THIRD_QUARTILE"),
          contribution_day(Date.new(2026, 8, 23), 1, "FIRST_QUARTILE")
        ]
      )
    )

    result = Github::SyncContributions.new(
      connection: @connection,
      now: Time.utc(2026, 8, 23, 0, 50),
      calendar_client: calendar,
      access_token_client: FakeAccessTokenFactory.new
    ).call

    assert_equal Date.new(2026, 8, 22), result.from_date
    assert_equal Date.new(2026, 8, 22), result.to_date
    assert_equal Date.new(2026, 8, 21), calendar.calls.first.fetch(:from_date)
    assert_equal Date.new(2026, 8, 23), calendar.calls.first.fetch(:to_date)
    assert_equal [ [ Date.new(2026, 8, 22), 3 ] ],
      @connection.daily_contributions.pluck(:activity_date, :contribution_count)
  end

  test "rejects a token for a different GitHub identity without saving days" do
    calendar = FakeCalendarFactory.new(result: calendar_result(github_database_id: 84))

    error = assert_raises Github::SyncContributions::IdentityMismatch do
      sync(calendar:)
    end

    assert_equal "GitHub token belongs to a different account", error.message
    assert_empty @connection.daily_contributions
    assert_predicate @connection, :sync_status_error?
    assert_equal Github::SyncContributions::STORED_ERROR_MESSAGE, @connection.last_sync_error
  end

  test "records a sanitized retryable error when GitHub is unavailable" do
    previous_sync = NOW - 1.day
    @connection.update!(sync_status: "ready", last_synced_at: previous_sync)
    provider_error = Github::ContributionCalendar::Error.new("provider details")
    calendar = FakeCalendarFactory.new(error: provider_error)

    error = assert_raises Github::SyncContributions::Error do
      sync(calendar:)
    end

    assert_equal "GitHub contributions could not be synchronized", error.message
    assert_same provider_error, error.cause
    assert_empty @connection.daily_contributions
    assert_predicate @connection, :sync_status_error?
    assert_equal Github::SyncContributions::STORED_ERROR_MESSAGE, @connection.last_sync_error
    assert_not_includes @connection.last_sync_error, "provider details"
    assert_equal previous_sync, @connection.last_synced_at
  end

  test "marks the connection failed when credential refresh requires reauthorization" do
    access_token = FakeAccessTokenFactory.new(
      error: Github::AccessToken::ReauthorizationRequired.new("provider details")
    )
    calendar = FakeCalendarFactory.new(result: calendar_result)

    error = assert_raises Github::SyncContributions::ReauthorizationRequired do
      sync(calendar:, access_token:)
    end

    assert_equal "GitHub reauthorization is required", error.message
    assert_empty calendar.calls
    assert_predicate @connection, :sync_status_reauthorization_required?
    assert_equal Github::SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE, @connection.last_sync_error
    assert_not_includes @connection.last_sync_error, "provider details"
  end

  test "does not start another request while the connection is synchronizing" do
    @connection.update!(sync_status: "syncing")
    calendar = FakeCalendarFactory.new(result: calendar_result)

    assert_raises Github::SyncContributions::AlreadySyncing do
      sync(calendar:)
    end

    assert_empty calendar.calls
    assert_predicate @connection, :sync_status_syncing?
  end

  test "runs a queued request only through the durable queued transition" do
    @connection.update!(sync_status: "queued")
    calendar = FakeCalendarFactory.new(result: calendar_result)

    sync(calendar:, require_queued: true)

    assert_predicate @connection, :sync_status_ready?
  end

  test "does not let a direct synchronization race a queued job" do
    @connection.update!(sync_status: "queued")
    calendar = FakeCalendarFactory.new(result: calendar_result)

    assert_raises Github::SyncContributions::AlreadySyncing do
      sync(calendar:)
    end

    assert_empty calendar.calls
    assert_predicate @connection, :sync_status_queued?
  end

  private
    def sync(
      calendar:,
      now: NOW,
      access_token: Github::AccessToken,
      require_queued: false
    )
      Github::SyncContributions.new(
        connection: @connection,
        today: TODAY,
        now:,
        calendar_client: calendar,
        access_token_client: access_token,
        require_queued:
      ).call
    end

    def calendar_result(
      github_database_id: 42,
      today_count: 2,
      today_level: "SECOND_QUARTILE",
      days: nil
    )
      {
        github_login: "octocat",
        github_database_id:,
        days: days || [
          contribution_day(Date.new(2026, 8, 20), 4, "THIRD_QUARTILE"),
          contribution_day(Date.new(2026, 8, 21), 0, "NONE"),
          contribution_day(TODAY, today_count, today_level)
        ]
      }
    end

    def contribution_day(date, count, level)
      {
        activity_date: date,
        contribution_count: count,
        contribution_level: level
      }
    end
end
