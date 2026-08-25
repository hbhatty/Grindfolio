class Session < ApplicationRecord
  COOKIE_NAME = :grindfolio_session_id
  IDLE_TIMEOUT = 7.days
  ABSOLUTE_TIMEOUT = 30.days
  ACTIVITY_REFRESH_CADENCE = 1.hour

  belongs_to :user

  before_validation :set_expiration_defaults, on: :create

  validates :last_seen_at, :expires_at, presence: true
  validate :expires_after_last_seen

  def active?(at: Time.current)
    !expired?(at:)
  end

  def expired?(at: Time.current)
    last_seen_at <= at - IDLE_TIMEOUT || expires_at <= at
  end

  def activity_refresh_due?(at: Time.current)
    last_seen_at <= at - ACTIVITY_REFRESH_CADENCE
  end

  def refresh_activity!(at: Time.current)
    return false unless activity_refresh_due?(at:)

    with_lock do
      return false unless activity_refresh_due?(at:)

      update!(last_seen_at: at)
    end

    true
  end

  private
    def set_expiration_defaults
      now = Time.current
      self.last_seen_at ||= now
      self.expires_at ||= now + ABSOLUTE_TIMEOUT
    end

    def expires_after_last_seen
      return if last_seen_at.blank? || expires_at.blank?
      return if expires_at > last_seen_at

      errors.add(:expires_at, "must be after the last activity time")
    end
end
