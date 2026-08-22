require "test_helper"

class SessionTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 8, 21, 12)

  test "sets the confirmed expiration defaults" do
    travel_to NOW do
      session = Session.create!(user: User.create!)

      assert_equal NOW, session.last_seen_at
      assert_equal NOW + 30.days, session.expires_at
      assert session.active?
    end
  end

  test "expires after seven idle days" do
    session = build_session

    assert session.active?(at: NOW + 7.days - 1.second)
    assert session.expired?(at: NOW + 7.days)
  end

  test "expires at the absolute expiration time" do
    session = build_session(last_seen_at: NOW + 29.days)

    assert session.active?(at: NOW + 30.days - 1.second)
    assert session.expired?(at: NOW + 30.days)
  end

  test "refreshes activity at most once per cadence" do
    session = Session.create!(
      user: User.create!,
      last_seen_at: NOW,
      expires_at: NOW + 30.days
    )

    assert_not session.refresh_activity!(at: NOW + 1.hour - 1.second)
    assert_equal NOW, session.reload.last_seen_at

    assert session.refresh_activity!(at: NOW + 1.hour)
    assert_equal NOW + 1.hour, session.reload.last_seen_at

    assert_not session.refresh_activity!(at: NOW + 2.hours - 1.second)
    assert_equal NOW + 1.hour, session.reload.last_seen_at
  end

  test "refreshing activity preserves absolute expiration" do
    session = Session.create!(
      user: User.create!,
      last_seen_at: NOW + 29.days - 2.hours,
      expires_at: NOW + 30.days
    )

    assert session.refresh_activity!(at: NOW + 29.days)
    assert_equal NOW + 29.days, session.reload.last_seen_at
    assert_equal NOW + 30.days, session.expires_at
    assert session.active?(at: NOW + 30.days - 1.second)
    assert session.expired?(at: NOW + 30.days)
  end

  test "requires expiration after the last activity" do
    session = Session.new(
      user: User.create!,
      last_seen_at: NOW,
      expires_at: NOW
    )

    assert_not session.valid?
    assert_includes session.errors[:expires_at], "must be after the last activity time"
  end

  test "is destroyed with its user" do
    user = User.create!
    session = user.sessions.create!

    assert_difference -> { Session.count }, -1 do
      user.destroy!
    end
    assert_not Session.exists?(session.id)
  end

  private
    def build_session(last_seen_at: NOW)
      Session.new(
        user: User.new,
        last_seen_at:,
        expires_at: NOW + 30.days
      )
    end
end
