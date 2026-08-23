require "test_helper"

class Github::SyncContributionsJobTest < ActiveJob::TestCase
  setup do
    user = User.create!
    identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "42",
      provider_username: "octocat"
    )
    @connection = identity.create_github_connection!(
      tracking_started_on: Date.new(2026, 8, 23),
      access_token: "access-token",
      refresh_token: "refresh-token",
      access_token_expires_at: Time.utc(2026, 8, 23, 20)
    )
  end

  test "finishes harmlessly when the connection was deleted before execution" do
    connection_id = @connection.id
    @connection.destroy!

    assert_nothing_raised do
      Github::SyncContributionsJob.perform_now(connection_id)
    end
  end

  test "finishes harmlessly when another synchronization is already running" do
    @connection.update!(sync_status: "syncing")

    assert_nothing_raised do
      Github::SyncContributionsJob.perform_now(@connection.id)
    end

    assert_predicate @connection.reload, :sync_status_syncing?
  end

  test "finishes harmlessly when a duplicate job runs after the queued state is gone" do
    %w[pending ready error].each do |status|
      @connection.update!(sync_status: status)

      assert_nothing_raised do
        Github::SyncContributionsJob.perform_now(@connection.id)
      end

      assert_equal status, @connection.reload.sync_status
    end
  end
end
